+++
title = 'Kubernetes LoadBalancer Services with Cilium BGP Control Plane, MikroTik Integration, and Gateway API Support'
date = 2025-11-27T18:30:58Z
tags = ['Home Lab', 'Talos', 'Kubernetes', 'Cilium']
draft = false
+++

## Overview

This guide demonstrates how to configure Cilium on Talos Linux to provide LoadBalancer services with BGP integration using a MikroTik router, and how to leverage the Gateway API for advanced traffic management.

You will learn how to:

* Install and configure Cilium CNI on Talos Linux
* Set up BGP Control Plane with Cilium for dynamic route advertisement
* Configure BGP peering between Cilium nodes and a MikroTik router
* Create and manage LoadBalancer IP pools for external and internal services
* Install and configure Gateway API CRDs
* Deploy and verify Gateway resources with IP pool allocation
* Create HTTPRoute resources for advanced traffic routing

The configuration enables automatic IP address allocation from different CIDR ranges based on service labels, with BGP automatically advertising these routes to your network infrastructure. This provides a seamless way to expose Kubernetes services to your network without manual IP management.

## Configure Cilium BGP Control Plane with MikroTik

### Cilium installation

In this guide, you will learn how to set up Cilium CNI on Talos.

#### Install the Cilium CLI

**Linux:**

```
CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
CLI_ARCH=amd64
if [ "$(uname -m)" = "aarch64" ]; then CLI_ARCH=arm64; fi
curl -L --fail --remote-name-all https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}
sha256sum --check cilium-linux-${CLI_ARCH}.tar.gz.sha256sum
sudo tar xzvfC cilium-linux-${CLI_ARCH}.tar.gz /usr/local/bin
rm cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}
```

**macOS:**

```
CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
CLI_ARCH=amd64
if [ "$(uname -m)" = "arm64" ]; then CLI_ARCH=arm64; fi
curl -L --fail --remote-name-all https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-darwin-${CLI_ARCH}.tar.gz{,.sha256sum}
shasum -a 256 -c cilium-darwin-${CLI_ARCH}.tar.gz.sha256sum
sudo tar xzvfC cilium-darwin-${CLI_ARCH}.tar.gz /usr/local/bin
rm cilium-darwin-${CLI_ARCH}.tar.gz{,.sha256sum}
```

> Cilium can be installed either via the Cilium CLI or using Helm.

#### Install Gateway API CRDs

If you plan to use the Gateway API with Cilium, you should install the required CRDs before installing Cilium. This ensures that the Cilium operator is aware of the Gateway API CRDs when it starts.

You can install the required CRDs like this:

```
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.2.0/config/crd/standard/gateway.networking.k8s.io_gatewayclasses.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.2.0/config/crd/standard/gateway.networking.k8s.io_gateways.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.2.0/config/crd/standard/gateway.networking.k8s.io_httproutes.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.2.0/config/crd/standard/gateway.networking.k8s.io_referencegrants.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.2.0/config/crd/standard/gateway.networking.k8s.io_grpcroutes.yaml
```

#### Installation using Helm

Install the latest stable version.

```
CILIUM_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium/main/stable.txt | sed 's/^v//')
```

> **Note:** At the time of writing this blog, the latest stable version of Cilium is 1.8.4.

```
helm repo add cilium https://helm.cilium.io/

helm install \
    cilium \
    cilium/cilium \
    --version $CILIUM_VERSION \
    --namespace kube-system \
    --set ipam.mode=kubernetes \
    --set bgpControlPlane.enabled=true \
    --set kubeProxyReplacement=true \
    --set securityContext.capabilities.ciliumAgent="{NET_BIND_SERVICE,CHOWN,KILL,NET_ADMIN,NET_RAW,IPC_LOCK,SYS_ADMIN,SYS_RESOURCE,DAC_OVERRIDE,FOWNER,SETGID,SETUID}" \
    --set securityContext.capabilities.cleanCiliumState="{NET_ADMIN,SYS_ADMIN,SYS_RESOURCE}" \
    --set cgroup.autoMount.enabled=false \
    --set cgroup.hostRoot=/sys/fs/cgroup \
    --set k8sServiceHost=localhost \
    --set k8sServicePort=7445 \
    --set=gatewayAPI.enabled=true \
    --set=gatewayAPI.enableAlpn=true \
    --set=gatewayAPI.enableAppProtocol=true
```

To validate that Cilium has been properly installed, you can run:

```
cilium status
```

> Output:

```
    /¯¯\
 /¯¯\__/¯¯\    Cilium:             OK
 \__/¯¯\__/    Operator:           OK
 /¯¯\__/¯¯\    Envoy DaemonSet:    OK
 \__/¯¯\__/    Hubble Relay:       disabled
    \__/       ClusterMesh:        disabled

DaemonSet              cilium                   Desired: 1, Ready: 1/1, Available: 1/1
DaemonSet              cilium-envoy             Desired: 1, Ready: 1/1, Available: 1/1
Deployment             cilium-operator          Desired: 1, Ready: 1/1, Available: 1/1
Containers:            cilium                   Running: 1
                       cilium-envoy             Running: 1
                       cilium-operator          Running: 1
                       clustermesh-apiserver    
                       hubble-relay             
Cluster Pods:          2/2 managed by Cilium
Helm chart version:    1.18.4
Image versions         cilium             quay.io/cilium/cilium:v1.18.4@sha256:49d87af187eeeb9e9e3ec2bc6bd372261a0b5cb2d845659463ba7cc10fe9e45f: 1
                       cilium-envoy       quay.io/cilium/cilium-envoy:v1.34.10-1762597008-ff7ae7d623be00078865cff1b0672cc5d9bfc6d5@sha256:1deb6709afcb5523579bf1abbc3255adf9e354565a88c4a9162c8d9cb1d77ab5: 1
                       cilium-operator    quay.io/cilium/operator-generic:v1.18.4@sha256:1b22b9ff28affdf574378a70dade4ef835b00b080c2ee2418530809dd62c3012: 1
```

### Cilium BGP Control Plane

#### BGP Cluster Configuration

Cilium BGP control plane is managed by a set of custom resources which provide a flexible way to configure BGP peers, policies, and advertisements.

The following resources are used to manage the BGP Control Plane:

* CiliumBGPClusterConfig: Defines BGP instances and peer configurations that are applied to multiple nodes.
* CiliumBGPPeerConfig: A common set of BGP peering settings. It can be used across multiple peers.
* CiliumBGPAdvertisement: Defines prefixes that are injected into the BGP routing table.

Here is an example configuration of the CiliumBGPClusterConfig with a BGP instance named `instance-65000` and a MikroTik peer, which is my home router. We are using `autoDiscovery` mode `DefaultGateway` so that it discovers the IP of the MikroTik router since it is our default gateway address.

```
kubectl apply -f - <<EOF
apiVersion: cilium.io/v2
kind: CiliumBGPClusterConfig
metadata:
  name: cilium-bgp
spec:
  nodeSelector:
    matchLabels:
      "cilium-enable-bgp": "true"
  bgpInstances:
  - name: "instance-65000"
    localASN: 65000
    localPort: 179
    peers:
    - name: "mikrotik-65000"
      peerASN: 65000
      autoDiscovery:
        mode: "DefaultGateway"
        defaultGateway:
          addressFamily: ipv4
      peerConfigRef:
        name: "cilium-peer"
EOF
```

```
k get cbgpcluster
```

The `nodeSelector` section specifies which nodes in the cluster should have this BGP configuration applied. BGP configuration is applied to one or more nodes in the cluster based on their nodeSelector. In this example, only nodes with the label `cilium-enable-bgp: "true"` will have the BGP configuration applied.

#### BGP Peer Configuration

The `CiliumBGPPeerConfig` resource is used to define a BGP peer configuration. Multiple peers can share the same configuration and provide reference to the common `CiliumBGPPeerConfig` resource.

The CiliumBGPPeerConfig resource contains configuration options for:

* MD5 Password
* Timers
* EBGP Multihop
* Graceful Restart
* Transport
* Address Families

**MD5 Password**

`AuthSecretRef` in `CiliumBGPPeerConfig` can be used to configure an RFC-2385 TCP MD5 password on the session with the BGP peer which references this configuration.

An example of creating a secret:

```
BGP_PASS=$(openssl rand -base64 32 | tr -dc 'A-Za-z0-9' | head -c20)

kubectl create secret generic -n kube-system \
  bgp-auth-secret \
  --type=string \
  --from-literal=password="${BGP_PASS}"
```

> `AuthSecretRef` should reference the name of a secret in the BGP secrets namespace (if using the Helm chart, this is `kube-system` by default). The secret should contain a key named `password`.

To retrieve the password from the secret (for use in RouterOS configuration):

```
kubectl -n kube-system get secret bgp-auth-secret -o jsonpath='{.data.password}' | base64 -d; echo
```


Here is an example of a `CiliumBGPPeerConfig` resource with `authSecretRef`:


```
kubectl apply -f - <<EOF
apiVersion: cilium.io/v2
kind: CiliumBGPPeerConfig
metadata:
  name: cilium-peer
spec:
  timers:
    holdTimeSeconds: 9
    keepAliveTimeSeconds: 3
  authSecretRef: bgp-auth-secret
  ebgpMultihop: 4
  gracefulRestart:
    enabled: true
    restartTimeSeconds: 15
  families:
    - afi: ipv4
      safi: unicast
      advertisements:
        matchLabels:
          advertise: "bgp"
EOF
```

```
k get cbgppeer
```

#### Configure BGP Peering on MikroTik Router

To establish BGP peering between your MikroTik router and Talos Linux Cilium nodes, you need to configure the BGP connection on the RouterOS side. This configuration should match the BGP settings defined in your Cilium BGP Cluster Configuration.

**Prerequisites:**
- The MikroTik router should have the BGP routing package installed
- You should know the IP address of your Talos/Cilium node(s)
- The ASN (Autonomous System Number) should match between Cilium and MikroTik
- If you are using MD5 authentication, you will need the same password configured on both sides

**RouterOS BGP Connection Configuration:**

Use the following RouterOS command to create a BGP connection. Replace the values according to your environment:

```
/routing/bgp/connection/add \
  name=test2 \
  remote.address=192.168.88.210 \
  as=65000 \
  address-families=ip \
  local.role=ibgp \
  local.port=179 \
  connect=yes \
  listen=yes \
  remote.port=179 \
  tcp-md5-key=xxxxxx \
  comment=talos-cilium-65000
```

**Parameter Explanation:**
- `name`: A descriptive name for the BGP connection
- `remote.address`: The IP address of your Talos/Cilium node
- `as`: The Autonomous System Number (should match the `localASN` in CiliumBGPClusterConfig)
- `address-families`: Set to `ip` for IPv4 unicast routes
- `local.role`: Set to `ibgp` for iBGP (same ASN) or `ebgp` for eBGP (different ASN)
- `local.port`: Local BGP port (default is 179)
- `connect=yes`: Enable active connection attempts
- `listen=yes`: Enable listening for incoming connections
- `remote.port`: Remote BGP port (default is 179)
- `tcp-md5-key`: MD5 authentication key (must match the password in your Kubernetes secret)
- `comment`: Optional description for the connection

> **Note:** If you are not using MD5 authentication, you can omit the `tcp-md5-key` parameter. However, it is recommended to use authentication for security in production environments.

**Alternative: Using RouterOS Web Interface (Winbox)**

You can also configure BGP peering through the RouterOS web interface:
1. Navigate to **Routing** → **BGP** → **Connections**
2. Click the **+** button to add a new connection
3. Fill in the connection details matching the parameters above
4. Click **OK** to save


**Verification**

**Verify BGP session from the Cilium side:**

To verify that BGP sessions are established with the auto-discovered peers, use the cilium bgp peers command:

```
❯ cilium bgp peers
Node                Local AS   Peer AS   Peer Address   Session State   Uptime   Family         Received   Advertised
cilium-lab-ctrl-1   65000      65000     192.168.88.1   established     1m19s    ipv4/unicast   0          1  
```


**Verify BGP from the MikroTik side:**

To verify that BGP sessions are established with the auto-discovered peers, use the following command:

```
/routing/bgp/session/print where name=test2
```

> Output:

```
Flags: E - established
 0 E name="test2-1"
     remote.address=192.168.88.210 .as=65000 .id=192.168.88.210 .capabilities=mp,rr,enhe,gr,as4,fqdn .hold-time=9s .messages=10 .bytes=194 .gr-time=15 .gr-afi=ip .eor=ip
     local.role=ibgp .address=192.168.88.1 .as=65000 .id=192.168.90.1 .capabilities=mp,rr,gr,as4 .messages=10 .bytes=190 .eor=""
     output.procid=23
     input.procid=23 ibgp
     multihop=yes hold-time=9s keepalive-time=3s uptime=27s110ms last-started=2025-11-27 20:17:29 prefix-count=0
```

> **Note:** Both Cilium and RouterOS BGP instances should show the `established` flag/state. In Cilium, this appears as `Session State: established` in the `cilium bgp peers` output. In RouterOS, this appears as the `E` flag in the session list. This flag indicates that a BGP session has been successfully established between the peers.


#### BGP Advertisements

The `CiliumBGPAdvertisement` resource is used to define various advertisement types and attributes associated with them.

The following advertisement types are supported by Cilium:

* Pod CIDR ranges
* Service Virtual IPs

**Service Virtual IPs**

In Kubernetes, a Service can have multiple virtual IP addresses, such as `.spec.clusterIP`, `.spec.clusterIPs`, `.status.loadBalancer.ingress[*].ip`, or `.spec.externalIPs`.

The `.selector` field is a label selector that selects Services matching the specified `.matchLabels` or `.matchExpressions`.

Here is an example configuration:

```
kubectl apply -f - <<EOF
apiVersion: cilium.io/v2
kind: CiliumBGPAdvertisement
metadata:
  name: bgp-advertisements
  labels:
    advertise: bgp
spec:
  advertisements:
    - advertisementType: "Service"
      service:
        addresses:
          - LoadBalancerIP
          - ExternalIP
      selector:
        matchExpressions:
          - {key: service-type, operator: In, values: ['internal', 'external']}
EOF
```

```
k get cbgpadvert
NAME                 AGE
bgp-advertisements   3m6s
```

#### CiliumLoadBalancerIPPool

The `CiliumLoadBalancerIPPool` resource defines IP address pools that can be allocated to LoadBalancer services. You can create multiple pools with different CIDR ranges and use service selectors to determine which pool should be used for a specific service.

Here is an example configuration creating two IP pools (internal and external):

```
kubectl apply -f - <<EOF
apiVersion: "cilium.io/v2"
kind: CiliumLoadBalancerIPPool
metadata:
  name: "external-pool"
  labels:
    service-type: external
spec:
  allowFirstLastIPs: "No"
  blocks:
  - cidr: "192.168.77.0/24"
  serviceSelector:
    matchExpressions:
      - {key: service-type, operator: In, values: [external]}
---
apiVersion: "cilium.io/v2"
kind: CiliumLoadBalancerIPPool
metadata:
  name: "internal-pool"
  labels:
    service-type: internal
spec:
  allowFirstLastIPs: "No"
  blocks:
  - cidr: "192.168.78.0/24"
  serviceSelector:
    matchExpressions:
      - {key: service-type, operator: In, values: [internal]}
EOF
```

```
k get ippools
NAME            DISABLED   CONFLICTING   IPS AVAILABLE   AGE
external-pool   false      False         254             2m54s
internal-pool   false      False         254             29s
```

#### Validate LoadBalancer External IP

Now let us create pods with a service type LoadBalancer and test them.

Create two nginx pods:

```
kubectl run nginx-internal --image=nginx:latest --port=80 --labels="app=nginx-internal"

kubectl run nginx-external --image=nginx:latest --port=80 --labels="app=nginx-external"
```

Create a service type `LoadBalancer` called nginx-internal with label `service-type: "internal"` so that an IP from the `internal-pool` is allocated:

```
kubectl expose pod nginx-internal \
  --port 80 \
  --target-port 80 \
  --name nginx-internal \
  --type=LoadBalancer \
  --overrides='{
    "metadata":{
      "labels":{"service-type":"internal"}
    }
  }'
```

Create a service type `LoadBalancer` called nginx-external with label `service-type: "external"` so that an IP from the `external-pool` is allocated:

```
kubectl expose pod nginx-external \
  --port 80 \
  --target-port 80 \
  --name nginx-external \
  --type=LoadBalancer \
  --overrides='{
    "metadata":{
      "labels":{"service-type":"external"}
    }
  }'
```

Check services:

```
❯ k get service
NAME             TYPE           CLUSTER-IP      EXTERNAL-IP    PORT(S)                  AGE
nginx-external   LoadBalancer   10.99.221.242   192.168.77.1   80:31971/TCP             3h19m
nginx-internal   LoadBalancer   10.105.1.38     192.168.78.1   80:30723/TCP             3h18m
```

Check BGP routing advertisement from the Cilium side:

```
cilium bgp routes

Node                VRouter   Prefix            NextHop   Age       Attrs
cilium-lab-ctrl-1   65000     192.168.77.1/32   0.0.0.0   3h7m31s   [{Origin: i} {Nexthop: 0.0.0.0}]   
                    65000     192.168.78.1/32   0.0.0.0   3h7m31s   [{Origin: i} {Nexthop: 0.0.0.0}]
```

Check BGP routing advertisement from the MikroTik side:

```
/ip route print where bgp
Flags: D - DYNAMIC; A - ACTIVE; b - BGP
Columns: DST-ADDRESS, GATEWAY, DISTANCE
    DST-ADDRESS      GATEWAY         DISTANCE
DAb 10.244.0.0/24    192.168.88.201       200
DAb 10.244.1.0/24    192.168.88.200       200
DAb 10.244.2.0/24    192.168.88.202       200
DAb 172.16.88.1/32   192.168.88.200       200
D b 172.16.88.1/32   192.168.88.202       200
D b 172.16.88.1/32   192.168.88.201       200
DAb 172.16.88.2/32   192.168.88.200       200
D b 172.16.88.2/32   192.168.88.202       200
D b 172.16.88.2/32   192.168.88.201       200
DAb 192.168.77.1/32  192.168.88.210       200
DAb 192.168.78.1/32  192.168.88.210       200
```

Test connectivity to the service external IP:

```
curl -I 192.168.77.1

HTTP/1.1 200 OK
Server: nginx/1.29.3
Date: Fri, 28 Nov 2025 13:13:48 GMT
Content-Type: text/html
Content-Length: 615
Last-Modified: Tue, 28 Oct 2025 12:05:10 GMT
Connection: keep-alive
ETag: "6900b176-267"
Accept-Ranges: bytes
```

```
curl -I 192.168.78.1

HTTP/1.1 200 OK
Server: nginx/1.29.3
Date: Fri, 28 Nov 2025 13:14:17 GMT
Content-Type: text/html
Content-Length: 615
Last-Modified: Tue, 28 Oct 2025 12:05:10 GMT
Connection: keep-alive
ETag: "6900b176-267"
Accept-Ranges: bytes
```

## Cilium Gateway API

Gateway API is a Kubernetes SIG-Network subproject designed to be a successor for the Ingress object. It is a set of resources that model service networking in Kubernetes, and is designed to be role-oriented, portable, expressive, and extensible.

### Cilium Gateway API Support

Cilium supports Gateway API v1.2.0 for the following resources. All core conformance tests have passed.

* GatewayClass
* Gateway
* HTTPRoute
* GRPCRoute
* TLSRoute (experimental)
* ReferenceGrant

### Gateway

A Gateway has a 1:1 relationship with the lifecycle of infrastructure configuration. When a user creates a Gateway, load balancing infrastructure is provisioned or configured (see below for details) by the GatewayClass controller. In our case, we are using Cilium.

We are deploying two Gateways: one called `external-gateway` and one called `internal-gateway`. Each Gateway has a `service-type` label. The `external-gateway` has a `service-type` label of `external`, and the `internal-gateway` has a `service-type` label of `internal`. This is configured so that Cilium IP pool allocates different IP pools for external and internal CIDRs.

```
kubectl apply -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: external-gateway
spec:
  gatewayClassName: cilium
  infrastructure:
    labels:
      service-type: external
  listeners:
  - allowedRoutes:
      namespaces:
        from: Same
    name: web-gw
    port: 80
    protocol: HTTP
---
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: internal-gateway
spec:
  gatewayClassName: cilium
  infrastructure:
    labels:
      service-type: internal
  listeners:
  - allowedRoutes:
      namespaces:
        from: Same
    name: web-gw
    port: 80
    protocol: HTTP
EOF
```

### Verify Gateway Resources

To verify that the Gateway resources have been created successfully, use the following command:

```
k get gateway
```

> Output:

```
NAME               CLASS    ADDRESS        PROGRAMMED   AGE
external-gateway   cilium   192.168.77.2   True         6s
internal-gateway   cilium   192.168.78.2   True         6s
```

To check the detailed status conditions of a Gateway, you can use:

```
kubectl get gateway external-gateway -o json | jq -r .status.conditions
```

> Output:

```
[
  {
    "lastTransitionTime": "2025-11-29T11:30:14Z",
    "message": "Gateway successfully scheduled",
    "observedGeneration": 1,
    "reason": "Accepted",
    "status": "True",
    "type": "Accepted"
  },
  {
    "lastTransitionTime": "2025-11-29T11:30:14Z",
    "message": "Gateway Programmed",
    "observedGeneration": 1,
    "reason": "Programmed",
    "status": "True",
    "type": "Programmed"
  }
]
```

> **Note:** If you see a status message of "Waiting for controller", this is a known issue with the Cilium operator. The operator is unaware of Gateway API CRDs because they were installed after the operator was deployed. To fix this, restart the Cilium operator pods:

```
kubectl rollout restart deployment/cilium-operator -n kube-system
```

### HTTP Example

**Deploy the Demo Application**

```
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.11/samples/bookinfo/platform/kube/bookinfo.yaml
```



```
kubectl apply -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: http-app-1
spec:
  parentRefs:
  - name: internal-gateway
    namespace: default
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /details
    backendRefs:
    - name: details
      port: 9080
  - matches:
    - headers:
      - type: Exact
        name: magic
        value: foo
      queryParams:
      - type: Exact
        name: great
        value: example
      path:
        type: PathPrefix
        value: /
      method: GET
    backendRefs:
    - name: productpage
      port: 9080
EOF
```

The above example creates two Gateways named `internal-gateway` and `external-gateway` that listen on port 80. Two routes are defined: one for `/details` to the details service, and one for `/` to the productpage service. The routes are attached to the `internal-gateway`.

**Verify HTTP Requests**

Now that the Gateway is ready, you can make HTTP requests to the services:

```
GATEWAY=$(kubectl get gateway internal-gateway -o jsonpath='{.status.addresses[0].value}')

curl --fail -s http://"$GATEWAY"/details/1 | jq
{
  "id": 1,
  "author": "William Shakespeare",
  "year": 1595,
  "type": "paperback",
  "pages": 200,
  "publisher": "PublisherA",
  "language": "English",
  "ISBN-10": "1234567890",
  "ISBN-13": "123-1234567890"
}
```

```
curl -v -H 'magic: foo' http://"$GATEWAY"\?great\=example
...
<!DOCTYPE html>
<html>
  <head>
    <title>Simple Bookstore App</title>
<meta charset="utf-8">
<meta http-equiv="X-UA-Compatible" content="IE=edge">
<meta name="viewport" content="width=device-width, initial-scale=1">

<!-- Latest compiled and minified CSS -->
<link rel="stylesheet" href="static/bootstrap/css/bootstrap.min.css">

<!-- Optional theme -->
<link rel="stylesheet" href="static/bootstrap/css/bootstrap-theme.min.css">

  </head>
  <body>


<p>
    <h3>Hello! This is a simple bookstore application consisting of three services as shown below</h3>
</p>

<table class="table table-condensed table-bordered table-hover"><tr><th>name</th><td>http://details:9080</td></tr><tr><th>endpoint</th><td>details</td></tr><tr><th>children</th><td><table class="table table-condensed table-bordered table-hover"><tr><th>name</th><th>endpoint</th><th>children</th></tr><tr><td>http://details:9080</td><td>details</td><td></td></tr><tr><td>http://reviews:9080</td><td>reviews</td><td><table class="table table-condensed table-bordered table-hover"><tr><th>name</th><th>endpoint</th><th>children</th></tr><tr><td>http://ratings:9080</td><td>ratings</td><td></td></tr></table></td></tr></table></td></tr></table>

<p>
    <h4>Click on one of the links below to auto generate a request to the backend as a real user or a tester
    </h4>
</p>
<p><a href="/productpage?u=normal">Normal user</a></p>
<p><a href="/productpage?u=test">Test user</a></p>



<!-- Latest compiled and minified JavaScript -->
<script src="static/jquery.min.js"></script>

<!-- Latest compiled and minified JavaScript -->
<script src="static/bootstrap/js/bootstrap.min.js"></script>

  </body>
</html>
```