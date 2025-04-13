+++
title = 'Kubernetes Homelab, Part I: Talos Kubernetes on KVM using Terraform'
date = 2025-04-13T11:35:32+01:00
+++

## Overview

> You can find the Terraform code for this setup on [GitHub](https://github.com/shirwahersi/shirwalab-talos-infra)

Creating a homelab is a fantastic way to learn and experiment with new technologies. In this guide, we'll walk through setting up a homelab using Talos Linux and Kubernetes. Talos Linux is a minimal, hardened, and immutable Linux distribution designed specifically for Kubernetes. In this article, we’ll take a look at how to bootstrap a multi-node Talos cluster running in VMs on Libvirt/KVM. We’ll be using Terraform to do this declaratively, following Infrastructure as Code (IaC) principles.

## Hardware

The hardware used in this article is a Lenovo TS440 tower server with 32GB of RAM. For networking, we will use Cilium CNI with Talos. Cilium CNI also includes LoadBalancer IP Address Management (LB IPAM) for Kubernetes. LB IPAM is a feature that allows Cilium to assign IP addresses to services of type `LoadBalancer`. LB IPAM works in conjunction with features such as the Cilium BGP Control Plane. We will set up BGP peering between Cilium CNI and a Mikrotik router (Mikrotik hEX S) so that we can reach those service LoadBalancer IPs within our home network.

## Network topology

![homelab ](/static/images/homelab1.png)


| Device            | TYPE     | IP             |
|-------------------|----------|----------------|
| Mikrotik Router   | Hardware | 192.168.88.1   |
| Server1           | Hardware | 192.168.88.254 |
| talos-ctrl-1      | VM       | 192.168.88.200 |
| talos-work-1      | VM       | 192.168.88.201 |
| talos-work-2      | VM       | 192.168.88.202 |
| freeipa           | VM       | 192.168.88.100 |

## Setup

### Provisioning Talos libvirt VM's 

We will use Talos modules that take an argument called nodes, which is map of objects Talos nodes and their IP, MAC address, CPU, memory, etc. This ensures Talos nodes are provisioned with static IPs. We will instruct the Mikrotik router to lease the IP using the Terraform RouterOS provider and the routeros_ip_dhcp_server_lease resource.

```
# file: modules/talos/routeros.tf
resource "routeros_ip_dhcp_server_lease" "dhcp_lease" {
  for_each    = var.nodes
  address     = each.value.ip
  mac_address = each.value.mac_address
  comment     = "DHCP Lease for ${each.key}"
}
```

Talos nodes definitions:

```
# file: tfvars/shirwalab.tfvars
nodes = {
  "talos-ctrl-1" = {
    machine_type = "controlplane"
    ip           = "192.168.88.200"
    mac_address  = "e6:ae:2e:1e:b4:4e"
    cpu          = 2
    memory       = 2048
    disk_size    = 53687091200 # 50 GB
  }
  "talos-work-1" = {
    machine_type = "worker"
    ip           = "192.168.88.201"
    mac_address  = "aa:4f:3b:38:d7:7a"
    cpu          = 4
    memory       = 8192
    disk_size    = 1100585369600 # 1 TB
  }
  "talos-work-2" = {
    machine_type = "worker"
    ip           = "192.168.88.202"
    mac_address  = "1a:79:e6:90:d5:c0"
    cpu          = 4
    memory       = 8192
    disk_size    = 1100585369600 # 1 TB
  }
}

```

Talos Module Configuration:

```
# file: main.tf
module "talos" {
  source = "./modules/talos"

  providers = {
    routeros = routeros
  }

  image = {
    version   = "v1.9.5"
    schematic = file("${path.module}/files/image/schematic.yaml")
  }

  cluster = {
    name            = "talos-shirwalab"
    endpoint        = [for k, v in var.nodes : v.ip if v.machine_type == "controlplane"][0]
    gateway         = var.gateway_ip
    talos_version   = "v1.9"
    libvirt_cluster = "shirwalab"
  }

  nodes = var.nodes
}
```

### Talos cilium cni 

When generating the machine config for a node, set the CNI to none so that we can disable the default CNI. We also need to add the custom node label `cilium-enable-bgp: true`. This label is used by the Cilium BGP `CiliumBGPPeeringPolicy` and `CiliumLoadBalancerIPPool`, which allow Cilium to assign IP addresses to kubernetes services of type `LoadBalancer`.

```
# file: modules/talos/files/control-plane.yaml.tftpl
machine:
  install:
    diskSelector:
      size: '> 40GB'
    wipe: true
  network:
    hostname: ${hostname}
  nodeLabels:
    cilium-enable-bgp: true
    topology.kubernetes.io/region: ${cluster_name}

cluster:
  allowSchedulingOnControlPlanes: true
  network:
    cni:
      name: none
```

To install Cilium, we're using the Cilium Helm chart with the Terraform helm_release resource.

```
# file: cilium.tf
resource "helm_release" "cilium" {
  name = "cilium"

  repository = "https://helm.cilium.io/"
  chart      = "cilium"
  namespace  = "kube-system"
  version    = "1.17.2"

  values = ["${file("${path.module}/files/values/cilium.yaml")}"]

  depends_on = [module.talos]
}
```

#### Enable Cilium BGP control plane 

BGP Control Plane provides a way for Cilium to advertise routes to connected routers using the Border Gateway Protocol (BGP). The BGP Control Plane makes Pod networks and/or services reachable from outside the cluster in environments that support BGP.

I'm using a custom Helm chart called `cilium-bgp` to install two Cilium CRDs. The first one is the `CiliumBGPPeeringPolicy` CRD. All BGP peering topology information is carried in a CiliumBGPPeeringPolicy CRD. A CiliumBGPPeeringPolicy can be applied to one or more nodes based on its nodeSelector field. In our case, we are using the `cilium-enable-bgp: true` node label. Next, we define our virtual routers. Virtual routers allow multiple distinct routers to be supported within a single routed environment, enabling clusters to configure multiple, separate logical routers within a single network of nodes.

CiliumBGPPeeringPolicy also contains neighbors. This is typically the upstream router. In our case, this is our Mikrotik router In the example, we specify the same ASN (64512) as our nodes and the IP of our router: 192.168.88.1/32.

```
# file: charts/cilium-bgp/templates/bgp-peering-policy.yaml
apiVersion: "cilium.io/v2alpha1"
kind: CiliumBGPPeeringPolicy
metadata:
 name: {{ .Release.Name }}
spec:
 nodeSelector:
   matchLabels:
     cilium-enable-bgp: "true"
 virtualRouters:
 - localASN: {{ .Values.localASN  }}
   exportPodCIDR: true
   neighbors:
    - peerAddress: {{ .Values.peerAddress  }}
      peerASN: {{ .Values.peerASN  }}
   serviceSelector:
     matchExpressions:
       - {key: somekey, operator: NotIn, values: ['never-used-value']}
```

The second CRD installed by the `cilium-bgp` chart is `CiliumLoadBalancerIPPool`. When you create a LoadBalancer service in a Kubernetes cluster, the cluster itself does not actually assign the service a LoadBalancer IP (also known as an External IP); we need a plugin to do that. If you create a LoadBalancer service without a LoadBalancer plugin, the External IP address will show as "Pending" indefinitely.

The Cilium LoadBalancer IP Address Management (LB IPAM) feature can be used to provision IP addresses for our LoadBalancer services.

Here is what the official doc says about it:

> LB IPAM is a feature that allows Cilium to assign IP addresses to Services of type LoadBalancer. This functionality is usually left up to a cloud provider, however, when deploying in a private cloud environment, these facilities are not always available.

 This section must understand that LB IPAM is always enabled but dormant. The controller is awoken when the first IP Pool is added to the cluster.

```
# file: charts/cilium-bgp/templates/ippool.yaml
apiVersion: "cilium.io/v2alpha1"
kind: CiliumLoadBalancerIPPool
metadata:
  name: "{{ .Release.Name }}-ip-bool"
spec:
  blocks:
  - cidr: {{ .Values.cidr }}
  allowFirstLastIPs: "{{ .Values.allowFirstLastIPs }}"
```

Finally, we're also configuring the Mikrotik router to peer with Talos Cilium nodes.
We're using the Terraform routeros_routing_bgp_connection resource to create a BGP session between it and the Kubernetes Talos worker nodes.

```
# file: cilium.tf
resource "routeros_routing_bgp_connection" "talos_mikrotik_bgp_connection" {
  for_each         = var.nodes
  name             = "${each.key}-k8s-mikrotik_bgp-peering"
  as               = var.bgp_asn
  address_families = "ip"
  local {
    role = "ibgp"
  }
  remote {
    address = each.value.ip
  }
}

```

### Initialize and Apply Terraform

```
git clone https://github.com/shirwahersi/shirwalab-talos-infra.git
cd shirwalab-talos-infra

make ENVNAME=shirwalab init
make ENVNAME=shirwalab apply
```

## Verification

After provisioning the Talos nodes, verify the installation.

### 1. Verify KVM VMs

```
❯ sudo virsh list
 Id   Name           State
------------------------------
 1    freeipa        running
 2    talos-work-2   running
 3    talos-work-1   running
 4    pgsql1         running
 5    talos-ctrl-1   running
```

You can also use Cockpit web interface:

![homelab ](/static/images/Cockpit1.png)

### 2. Check Kubernetes Cluster Status

```
❯ k get nodes
NAME           STATUS   ROLES           AGE     VERSION
talos-ctrl-1   Ready    control-plane   4d21h   v1.32.0
talos-work-1   Ready    <none>          4d21h   v1.32.0
talos-work-2   Ready    <none>          4d21h   v1.32.0
```

### 3. Check Cilium CNI

Let’s check on cilium pods.

```
❯ k get pods -n kube-system
NAME                                   READY   STATUS    RESTARTS        AGE
cilium-54q2k                           1/1     Running   1 (4h30m ago)   4d21h
cilium-envoy-mb2h9                     1/1     Running   1 (4h30m ago)   4d21h
cilium-envoy-pzt7b                     1/1     Running   1 (4h30m ago)   4d21h
cilium-envoy-zx7dr                     1/1     Running   1 (4h30m ago)   4d21h
cilium-hdq7r                           1/1     Running   1 (4h30m ago)   4d21h
cilium-lx62s                           1/1     Running   1 (4h30m ago)   4d21h
cilium-operator-5556855979-gdcks       1/1     Running   1 (4h30m ago)   4d21h
cilium-operator-5556855979-rj2v7       1/1     Running   2 (4h30m ago)   4d21h
coredns-578d4f8ffc-cgxwk               1/1     Running   1 (4h30m ago)   4d21h
coredns-578d4f8ffc-jhv4w               1/1     Running   1 (4h30m ago)   4d21h
kube-apiserver-talos-ctrl-1            1/1     Running   0               4h28m
kube-controller-manager-talos-ctrl-1   1/1     Running   2 (4h29m ago)   4h28m
kube-proxy-5797s                       1/1     Running   1 (4h30m ago)   4d21h
kube-proxy-6dh4v                       1/1     Running   1 (4h30m ago)   4d21h
kube-proxy-bflwx                       1/1     Running   1 (4h30m ago)   4d21h
kube-scheduler-talos-ctrl-1            1/1     Running   2 (4h29m ago)   4h28m
```

Check cilium status using [cilium-cli](https://github.com/cilium/cilium-cli):

```
❯ cilium status
    /¯¯\
 /¯¯\__/¯¯\    Cilium:             OK
 \__/¯¯\__/    Operator:           OK
 /¯¯\__/¯¯\    Envoy DaemonSet:    OK
 \__/¯¯\__/    Hubble Relay:       disabled
    \__/       ClusterMesh:        disabled

Deployment             cilium-operator    Desired: 2, Ready: 2/2, Available: 2/2
DaemonSet              cilium-envoy       Desired: 3, Ready: 3/3, Available: 3/3
DaemonSet              cilium             Desired: 3, Ready: 3/3, Available: 3/3
Containers:            cilium             Running: 3
                       cilium-operator    Running: 2
                       cilium-envoy       Running: 3
Cluster Pods:          10/10 managed by Cilium
Helm chart version:
Image versions         cilium-operator    quay.io/cilium/operator-generic:v1.17.2@sha256:81f2d7198366e8dec2903a3a8361e4c68d47d19c68a0d42f0b7b6e3f0523f249: 2
                       cilium-envoy       quay.io/cilium/cilium-envoy:v1.31.5-1741765102-efed3defcc70ab5b263a0fc44c93d316b846a211@sha256:377c78c13d2731f3720f931721ee309159e782d882251709cb0fac3b42c03f4b: 3
                       cilium             quay.io/cilium/cilium:v1.17.2@sha256:3c4c9932b5d8368619cb922a497ff2ebc8def5f41c18e410bcc84025fcd385b1: 3
```

#### 3.1 Verify BGP from the Cilium side


The cilium cli provides a number of useful commands for checking BGP status. Use the “ peers “ command to display BGP Peer information:

```
❯ cilium bgp peers
Node           Local AS   Peer AS   Peer Address   Session State   Uptime   Family         Received   Advertised
talos-ctrl-1   64512      64512     192.168.88.1   established     1m22s    ipv4/unicast   0          1
                                                                            ipv6/unicast   0          0
talos-work-1   64512      64512     192.168.88.1   established     1m29s    ipv4/unicast   0          1
                                                                            ipv6/unicast   0          0
talos-work-2   64512      64512     192.168.88.1   established     38s      ipv4/unicast   0          1
                                                                            ipv6/unicast   0          0
```                                                                           

#### 3.2 Verify BGP from the Mikrotik side

Now we can see Cilium has sessions established, and we have Received and Advertised routes. Let’s check the router:

![homelab ](/static/images/cilium-mikrotik-peering.png)


#### 3.3 Validate LoadBalancer External IP

Now let’s create a pod with a service type LoadBalancer and test it.

Create nginx pod and `LoadBalancer` type service:
```
kubectl run nginx --image=nginx:latest --port=80 --labels="app=nginx"

kubectl expose pod nginx --port=80 --target-port=80 --type=LoadBalancer
```

Get service external-ip:

```
k get service nginx
NAME    TYPE           CLUSTER-IP      EXTERNAL-IP   PORT(S)        AGE
nginx   LoadBalancer   10.109.30.195   172.16.88.1   80:31419/TCP   13s
```

As you can from above, we have a service TYPE LoadBalancer with EXTERNAL-IP from our cilium ip-pool.

Test if you can connect to service external-ip:

```
curl 172.16.88.1

<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
<style>
html { color-scheme: light dark; }
body { width: 35em; margin: 0 auto;
font-family: Tahoma, Verdana, Arial, sans-serif; }
</style>
</head>
<body>
<h1>Welcome to nginx!</h1>
<p>If you see this page, the nginx web server is successfully installed and
working. Further configuration is required.</p>

<p>For online documentation and support please refer to
<a href="http://nginx.org/">nginx.org</a>.<br/>
Commercial support is available at
<a href="http://nginx.com/">nginx.com</a>.</p>

<p><em>Thank you for using nginx.</em></p>
</body>
</html>
```

## Sources:

* https://blog.stonegarden.dev/articles/2024/08/talos-proxmox-tofu/#cilium-bootstrap
* https://medium.com/@valentin.hristev/kubernetes-loadbalance-service-using-cilium-bgp-control-plane-8a5ad416546a