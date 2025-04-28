+++
title = 'Kubernetes Homelab, Part 2: Internal certificate and DNS management using cert-manager, external-dns, and FreeIPA.'
date = 2025-04-28T09:12:43+01:00
tags = ['Home Lab', 'Talos', 'Kubernetes']
draft = false
+++

Welcome back to our Kubernetes Homelab series! In Part 1, we set up our Kubernetes cluster using Talos Linux. Now, in Part 2, we'll dive into managing internal self signed certificates, DNS, and ingress using cert-manager, external-dns, NGINX controller, and FreeIPA. This setup ensures secure communication within your homelab and simplifies DNS management without exposing your services or IPs on the internet.

I already have a [FreeIPA](https://shirwalab.net/posts/free-ipa-rhel9-setup/) server that serves DNS on my home network. I want to continue using it to automatically configure my Kubernetes ingresses with ExternalDNS and Cert-Manager for creating self-signed certificates and DNS records.

## Prerequisites

* FreeIPA server set up for DNS and identity management.


## Lab overview

Our cluster setup from Part 1 is relatively basic with out-of-the-box Kubernetes components. To make it more useful, we add the following components:

1. An ingress controller, that can take incoming HTTP(S) connections and map them to services running in the cluster.
2. cert-manager, which can retrieve and update certificates for our HTTPS resources from the FreeIPA server.
3. external-dns, for managing our internal DNS records from the FreeIPA DNS server.

![homelab ](/static/images/homelab/homelab-dns-cert-ipa1.png)

## Lab Steps

### Step 1: Enable DNS dynamic updates and ACME support on the FreeIPA server.


#### 1.1 Create FreeIPA TSIG key

FreeIPA’s ACME service supports both HTTP-01 and DNS-01 challenges, but I generally prefer DNS-01. For cert-manager to add the _acme-challenge DNS record to FreeIPA, we can use cert-manager’s RFC-2136 provider.

To do this, we must create a new TSIG key on our IPA server:

```
tsig-keygen -a hmac-sha512 ipa-acme-update >> /etc/named/ipa-ext.conf
systemctl restart  named
```

Copy the TSIG key to AWS Secrets Manager so that both ExternalDNS and Cert-Manager can use it to authenticate to the FreeIPA server.

```
aws secretsmanager put-secret-value \
  --secret-id /homelab/ipa/acme-update-key \
  --secret-string "$(grep secret /etc/named/ipa-ext.conf | awk '{ print $2}')"
```

#### 1.2 Enable DDNS on your FreeIPA server

This step can be done via UI or CLI, but I did it via UI.

First, navigate to your DNS zone’s settings page.

Go to Network Services -> DNS -> DNS Zones then select your DNS zone

![FreeIPA Dyndns setup](/static/images/homelab/freeipa-dyndns1.png)

Click on Zone settings

![FreeIPA Dyndns setup](/static/images/homelab/freeipa-dyndns2.png)

Scroll down to where it says “Dynamic update” and set that to True. 

![FreeIPA Dyndns setup](/static/images/homelab/freeipa-dyndns3.png)


### Step 2: Install cert-manager

#### 2.1 Create cert-manager config map with Free-IPA CA cert

Before installing the cert-manager Helm chart, I had to modify my cert-manager installation slightly to include my own CA certificate bundle, which includes my IPA CA certificate. To do this, I first created the bundle and then created a Kubernetes ConfigMap for it.

FreeIPA server CA cert can be download at `https://<free-ipa-hostname>/ipa/config/ca.crt`

```
resource "kubernetes_namespace" "cert_manager" {
  metadata {
    name = "cert-manager"
  }
}

resource "kubernetes_config_map_v1" "ipa-ca-bundle" {
  metadata {
    name      = "ipa-ca-bundle"
    namespace = kubernetes_namespace.cert_manager.metadata[0].name
  }

  data = {
    "ca-certificates.crt" = "${file("${path.module}/files/helm/cert-manager/ipa-ca.crt")}"
  }
}
```

#### 2.1 Create cert-manager secret with FreeIPA TSIG key

So that cert-manager can authenticate to the FreeIPA DNS server for dynamically updating DNS records, create a TSIG key secret.

```
data "aws_secretsmanager_secret" "acme-update-key" {
  name = "/homelab/ipa/acme-update-key"
}

data "aws_secretsmanager_secret_version" "acme-update-key" {
  secret_id = data.aws_secretsmanager_secret.acme-update-key.id
}

resource "kubernetes_secret_v1" "acme-update" {
  metadata {
    name      = "ipa-tsig-secret"
    namespace = kubernetes_namespace.cert_manager.metadata[0].name
  }

  data = {
    rfc2136_tsig_secret = data.aws_secretsmanager_secret_version.acme-update-key.secret_string
  }
}
```

#### 2.3 Install cert-manager helm chart

Next, install cert-manager helm chart.

```
# file: terraform/infra-kube-addons/files/helm/cert-manager/cert-manager-values.yaml
---
crds:
  enabled: true
volumes:
  - name: ca-bundle
    configMap:
      name: ipa-ca-bundle
      items:
        - key: ca-certificates.crt
          path: ca-certificates.crt
volumeMounts:
  - name: ca-bundle
    mountPath: /etc/ssl/certs/ca-certificates.crt
    subPath: ca-certificates.crt
```

```
# file: terraform/infra-kube-addons/hem-addons-cert-manager.tf
resource "helm_release" "cert" {
  name = "cert-manager"

  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  namespace        = kubernetes_namespace.cert_manager.metadata[0].name
  create_namespace = false
  version          = "v1.17.2"

  values = ["${file("${path.module}/files/helm/cert-manager/cert-manager-values.yaml")}"]
}
```

#### 2.4 Create cert-manager ClusterIssuer

A ClusterIssuer in cert-manager is a cluster-scoped Custom Resource Definition (CRD) that represents a certificate authority (CA) capable of signing certificates in response to certificate signing requests. Unlike the Issuer resource, which is namespaced and can only issue certificates within its own namespace, a ClusterIssuer can issue certificates across all namespaces in a Kubernetes cluster.

Let's define a ClusterIssuer called ipa with our FreeIPA server URL:

```
resource "kubernetes_manifest" "cert_manager_cluster_issuer" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name      = "ipa"
    }
    spec = {
      acme = {
        email                 = "admin@int.shirwalab.net"
        server                = "https://idm.int.shirwalab.net/acme/directory"
        privateKeySecretRef = {
          name = "ipa-issuer-account-key"
        }
        solvers = [{
          dns01 = {
            rfc2136 = {
              nameserver = "idm.int.shirwalab.net"
              tsigKeyName = "acme-update"
              tsigAlgorithm = "HMACSHA512"
              tsigSecretSecretRef = {
                name = "ipa-tsig-secret"
                key  = "rfc2136_tsig_secret"
              }
            }
          }
          selector = {
            dnsZones = ["int.shirwalab.net"]
          }
        }]
      }
    }
  }

  depends_on = [ helm_release.cert ]
}
```

### Step 4: Install external-dns

ExternalDNS is a controller that monitors your cluster for domain name annotations on your services, NodePorts, and ingresses, and updates your DNS zone accordingly. We will use ExternalDNS with FreeIPA as the DNS provider.

First, define the ExternalDNS Helm values. We will configure ExternalDNS to use the RFC2136 provider, setting our FreeIPA server as the host and specifying the TSIG secrets to use:

```
# file: terraform/infra-kube-addons/files/helm/external-dns/external-dns-values.yaml
policy: sync
logLevel: debug
logFormat: json
domainFilters:
  - int.shirwalab.net # only handle DDNS for *.s.astrid.tech domains
provider: rfc2136
rfc2136:
  host: "idm.int.shirwalab.net"
  zone: "int.shirwalab.net"
  tsigSecretAlg: hmac-sha512
  tsigKeyname: acme-update
  secretName: ipa-tsig-secret
  tsigAxfr: false
```

Next, create external-dns namespace and install external-dns helm chert:

```
resource "kubernetes_namespace" "external_dns" {
  metadata {
    name = "external-dns"
  }
}

resource "kubernetes_secret_v1" "external_dns_ns_acme-update" {
  metadata {
    name      = "ipa-tsig-secret"
    namespace = kubernetes_namespace.external_dns.metadata[0].name
  }

  data = {
    rfc2136_tsig_secret = data.aws_secretsmanager_secret_version.acme-update-key.secret_string
  }
}

resource "helm_release" "external-dns" {
  name = "external-dns"

  repository       = "https://charts.bitnami.com/bitnami"
  chart            = "external-dns"
  namespace        = kubernetes_namespace.external_dns.metadata[0].name
  create_namespace = false
  version          = "8.3.9"

  values = ["${file("${path.module}/files/helm/external-dns/external-dns-values.yaml")}"]

}

```

### Step 5: Install Ingress Controller

There are many excellent ingress controllers available that support a wide range of use cases. However, since our needs are relatively simple, we'll use the official Kubernetes ingress-nginx controller.

```
# file: terraform/infra-kube-addons/helm-addons-nginx-ingress.tf
resource "helm_release" "ingress-nginx" {
  name = "ingress-nginx"

  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  namespace  = "kube-system"
  version    = "4.12.1"
}
```

### Step 7: Verify the Setup

#### 7.1: Create example app HTTPS ingress resource.

To validate the setup, let's create a deployment, service, and ingress resources using the hostname app1.int.shirwalab.net:

```
# file: app1.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app1
spec:
  selector:
    matchLabels:
      app: app1
  template:
    metadata:
      labels:
        app: app1
    spec:
      containers:
      - image: nginx
        name: nginx
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: app1
spec:
  selector:
    app: app1
  ports:
    - protocol: TCP
      port: 80
      targetPort: 80
  type: ClusterIP
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: app1
  annotations:
    cert-manager.io/issuer: "ipa"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - app1.int.shirwalab.net
    secretName: my-app1-tls
  rules:
  - host: app1.int.shirwalab.net
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: app1
            port:
              number: 80
```

Apply the manifest file:

```
k apply -f app1.yaml
```

Once the certificate is issued by the FreeIPA CA after a successful ACME DNS challenge, a secret containing the certificate with the READY state is created.

```
❯ k get cert
NAME          READY   SECRET        AGE
my-app1-tls   True    my-app1-tls   6m
```

#### 7.2: Verify DNS record and Cert creation on FreeIPA Server

Ensure the DNS record is created in FreeIPA by external-dns and the certificate is issued by cert-manager.

![Lab Part 2 Verify ](/static/images/homelab/freeipa-dns-record.png)


![Lab Part 2 Verify ](/static/images/homelab/freeipa-cert.png)


#### 7.3: Test app connectivity


```
curl -I https://app1.int.shirwalab.net
HTTP/2 200
date: Mon, 28 Apr 2025 11:38:07 GMT
content-type: text/html
content-length: 615
last-modified: Wed, 16 Apr 2025 12:01:11 GMT
etag: "67ff9c07-267"
accept-ranges: bytes
strict-transport-security: max-age=31536000; includeSubDomains
```

## Additional Information

Repository: The complete Terraform code for this lab can be found in my GitHub repo: https://github.com/shirwahersi/shirwalab-talos-infra

## Resources

* https://blog.hamzahkhan.com/using-freeipa-ca-as-an-acme-provider-for-cert-manager/
* https://astrid.tech/2021/04/18/0/k8s-freeipa-dns/
