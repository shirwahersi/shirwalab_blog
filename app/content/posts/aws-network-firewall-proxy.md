+++
title = 'AWS Network Firewall Proxy: Centralised Egress Filtering with NAT Gateway Integration'
date = 2026-01-23T00:00:00Z
tags = ['AWS', 'Network Firewall', 'Security', 'Terraform']
draft = false
+++

AWS Network Firewall Proxy, announced on November 24, 2025, is a preview feature that provides forward proxy capabilities integrated with NAT Gateways for centralised egress filtering. This guide walks you through deploying a hub-and-spoke architecture using AWS Network Firewall Proxy to control outbound traffic from your VPCs.

> **Note:** As of January 23, 2026, this feature is in preview and only available in the us-east-2 (Ohio) region.

## Key Benefits

* **Centralised egress filtering** across multiple VPCs
* **Domain-based traffic filtering** using PreDNS rules
* **Native AWS integration** without third-party appliances
* **Built on AWS-managed NAT Gateway infrastructure**
* **Reduced operational overhead**

## Use Cases

* Meeting compliance requirements by restricting outbound access
* Preventing unauthorised data exfiltration
* Controlling SaaS application access
* Managing external resources available to developers

## Architecture Overview

This lab implements a hub-and-spoke model:

* **APPVPC (spoke)**: Hosts applications without direct internet access
* **EgressProxyVPC (hub)**: Provides centralised egress through NFW Proxy and NAT Gateway
* Traffic routes through a VPC Interface Endpoint for domain filtering

![Architecture](/static/images/aws-nfw-proxy/nfw-proxy.png)

**Traffic Flow**

```
Test Instance (APPVPC Private Subnet)
         │
         ▼
VPC Endpoint (Interface)
         │
         ▼
Network Firewall Proxy ──────► Domain Filter Rules
         │                     (Allow: *.google.com, *.bbc.co.uk)
         ▼
NAT Gateway (EgressProxyVPC)
         │
         ▼
Internet Gateway
         │
         ▼
Internet
```

## Prerequisites

Before you begin, ensure you have:

* Terraform 1.x installed
* AWS CLI configured
* Valid AWS credentials with permissions in us-east-2
* SSH key pair for bastion access

## Deployment Steps

### 1. Clone the Repository

```bash
git clone git@github.com:shirwahersi/aws-network-firewall-proxy-lab.git
cd aws-network-firewall-proxy-lab
```

### 2. Configure Variables

Edit `variables.tf` to customise the AWS region and bastion trusted IPs for your environment.

```
# Change region if needed
variable "aws_region" {
  default = "us-east-2"
}

# Update trusted IPs for bastion access
variable "bastion_trusted_ips" {
  default = ["YOUR_IP/32"]
}
```

### 3. Deploy Infrastructure with Terraform

```bash
terraform init
terraform plan
terraform apply
```

### 4. Create Proxy Rule Group

> The NFW Proxy is a preview feature and must be created via AWS CLI or Console in eu-east-2 region. Currently, there is no terraform support for this feature.

The proxy rule group defines which domains are allowed or blocked:

```bash
aws network-firewall create-proxy-rule-group \
  --proxy-rule-group-name web-domain-filter \
  --description "egress domain filter" \
  --rules file://files/rules.json \
  --region us-east-2
```

**Proxy rule groups**

> Proxy rule groups contain the rules with conditions that determine whether internet traffic is allowed, denied or alerts you. 
> After a rule group is created, you can create a proxy configuration with at most ten rule groups. The rules and conditions that don't match your rule groups will default on the proxy configuration's default phase settings.

The rules.json contains PreDNS rules for filtering egress websites. Currently, this lab allows only the domains `*.google.com` and `*.bbc.co.uk`:

```
# files/rules.json

{
    "PreDNS": [
      {
        "ProxyRuleName": "domain-filter",
        "Description": "domain filter",
        "Action": "ALLOW",
        "Conditions": [
          {
            "ConditionOperator": "StringLike",
            "ConditionKey": "request:DestinationDomain",
            "ConditionValues": ["*.google.com", "*.bbc.co.uk"]
          }
        ]
      }
    ]
}
```

### 5. Create Proxy Configuration

Create the proxy configuration that references your rule group:

```bash
aws network-firewall create-proxy-configuration \
  --proxy-configuration-name "proxy-config" \
  --description "Proxy configuration" \
  --rule-group-names "web-domain-filter" \
  --default-rule-phase-actions PreDNS=DENY,PreREQUEST=ALLOW,PostRESPONSE=ALLOW \
  --region us-east-2
```

The proxy inspects your traffic at three different phases in the following order:

* **PreDNS** – applied before the proxy tries to resolve DNS for the desired destination domain
* **PreRequest** – applied before the proxy sends a HTTP request to the destination server
* **PostResponse** – applied after the proxy receives a HTTP response from the destination server

We deny traffic at the DNS resolution stage (PreDNS) unless the DNS host matches domains in the rules.json file. 

### 6. Retrieve NAT Gateway ID

Before creating the proxy, fetch the Nat Gateway ID to attach it to the proxy:

Get the NAT Gateway ID that will be associated with the proxy:

```bash
NGW_ID=$(aws ec2 describe-nat-gateways \
  --filter "Name=tag:Purpose,Values=egress-proxy" \
  --query "NatGateways[*].[NatGatewayId]" \
  --output text --region us-east-2)
```

### 7. Create the Proxy

Create the Network Firewall Proxy instance:

```bash
aws network-firewall create-proxy \
  --proxy-name "nfw-proxy" \
  --proxy-configuration-name "proxy-config" \
  --nat-gateway-id "$NGW_ID" \
  --listener-properties Port=1080,Type=HTTP Port=443,Type=HTTPS \
  --tls-intercept-properties "TlsInterceptMode=DISABLED" \
  --region us-east-2
```

> **Note:** Proxy deployment takes approximately 10-15 minutes.

### 8. Create VPC Endpoint

After the proxy is created, you need to create a VPC Endpoint in APPVPC to reach the proxy.

First, retrieve the VPC Endpoint Service Name:

```bash
aws network-firewall describe-proxy \
  --proxy-name "nfw-proxy" \
  --query "Proxy.VpcEndpointServiceName" \
  --output text --region us-east-2
```

> output

```
com.amazonaws.us-east-2.nfw.proxy.0005a154418a9f2cd
```

Then create the VPC Endpoint via the AWS Console:

1. Navigate to VPC > Endpoints
2. Click "Create endpoint"
3. Select the service name from the previous command

![VPC Endpoint](/static/images/aws-nfw-proxy/endpoint1.png)


4. Select APPVPC private subnets
5. Attach the `vpc-endpoint-app-vpc-sg` security group

![VPC Endpoint](/static/images/aws-nfw-proxy/endpoint2.png)

6. Click "Create endpoint"

## Testing

### Access the Test Instance

Use the bastion host to SSH into the test instance:

```bash
terraform output
ssh -i ~/.ssh/id_ed25519 -J ec2-user@<bastion_ip> ec2-user@<test_instance_ip>
```

### Configure Proxy Environment Variables

Set the proxy environment variables on the test instance:

```bash
export HTTP_PROXY=http://<vpce-endpoint>:1080
export HTTPS_PROXY=http://<vpce-endpoint>:1080
export NO_PROXY='amazonaws.com,127.0.0.1,localhost'
```

### Test Allowed Domains

Verify that allowed domains are accessible:

```bash
# Test google.com - should succeed
curl -I https://www.google.com
```

> output

```
HTTP/1.1 200 Connection Established

HTTP/2 200
content-type: text/html; charset=ISO-8859-1
content-security-policy-report-only: object-src 'none';base-uri 'self';script-src 'nonce-7Yna5HvrkRoeox7q8Lez3A' 'strict-dynamic' 'report-sample' 'unsafe-eval' 'unsafe-inline' https: http:;report-uri https://csp.withgoogle.com/csp/gws/other-hp
accept-ch: Sec-CH-Prefers-Color-Scheme
p3p: CP="This is not a P3P policy! See g.co/p3phelp for more info."
date: Thu, 22 Jan 2026 13:50:04 GMT
server: gws
x-xss-protection: 0
x-frame-options: SAMEORIGIN
expires: Thu, 22 Jan 2026 13:50:04 GMT
cache-control: private
set-cookie: AEC=AaJma5sgV82ts7JnD2Kry4uBy9SW8k4bWtOeiO2yEuRWWZ2rtWhcGKNawg; expires=Tue, 21-Jul-2026 13:50:04 GMT; path=/; domain=.google.com; Secure; HttpOnly; SameSite=lax
set-cookie: NID=528=ibKHe4dWoCOqmC9aKzPQYRamNkixyAQzDmuqlVJ6rjw5G607C2B5qD6GgxSKzLR0K2gkQEQ1XNlVU-vopN0xQaglogj920PalI6bu6ixiHqdNx1p6meVwgHKBydWmsP8MHqR41DM0GFp8MxBIE-shV7HYAngK-XnwAWeJhp4biReLsjnE_Vjndj7eRZs6Ssz977WLrsRaHsuVKf0XZzQ52rBjfRpTdDr_E0; expires=Fri, 24-Jul-2026 13:50:04 GMT; path=/; domain=.google.com; HttpOnly
set-cookie: __Secure-BUCKET=CK4D; expires=Tue, 21-Jul-2026 13:50:04 GMT; path=/; domain=.google.com; Secure; HttpOnly
alt-svc: h3=":443"; ma=2592000,h3-29=":443"; ma=2592000
```

Test connection to `www.bbc.co.uk` site:

```
# Test bbc.co.uk - should succeed
curl -I https://www.bbc.co.uk
```

> output

```
HTTP/1.1 200 Connection Established

HTTP/2 200
content-type: text/html
belfrage-cache-status: HIT
bid: bruce
brequestid: d8be1cc66652479c86976de7aaecacda
bsig: 1208f4af15d5afde4f19a9ad56d6a2c7
```

These should return `HTTP/1.1 200 OK` (or a redirect status).

### Test Blocked Domains

Verify that blocked domains are filtered:

```bash
# Test facebook.com - should be blocked
curl -I https://www.facebook.com
HTTP/1.1 403 Forbidden
Content-Type: text/plain; charset=utf-8
X-Content-Type-Options: nosniff
Date: Thu, 22 Jan 2026 13:52:23 GMT
Content-Length: 10

curl: (56) CONNECT tunnel failed, response 403
```

```bash
# Test github.com - should be blocked
curl -I https://www.github.com

HTTP/1.1 403 Forbidden
Content-Type: text/plain; charset=utf-8
X-Content-Type-Options: nosniff
Date: Thu, 22 Jan 2026 13:53:13 GMT
Content-Length: 10

curl: (56) CONNECT tunnel failed, response 403
```

Expected result: Connection refused or proxy error indicating domain is blocked.

## Cleanup

When you're finished with the lab, clean up resources in reverse order.

### 1. Delete VPC Endpoint

Navigate to VPC > Endpoints in the AWS Console and delete the endpoint.

### 2. Delete Proxy Components

```bash
aws network-firewall delete-proxy \
  --proxy-name "nfw-proxy" \
  --nat-gateway-id "$NGW_ID" \
  --region us-east-2

aws network-firewall delete-proxy-configuration \
  --proxy-configuration-name "proxy-config" \
  --region us-east-2

aws network-firewall delete-proxy-rule-group \
  --proxy-rule-group-name "web-domain-filter" \
  --region us-east-2
```

### 3. Destroy Terraform Infrastructure

```bash
terraform destroy
```

## References

* [AWS Network Firewall Proxy Lab Repository](https://github.com/shirwahersi/aws-network-firewall-proxy-lab)
* [Deployment models for AWS Network Firewall](https://docs.aws.amazon.com/network-firewall/latest/developerguide/architectures.html)
* [Securing egress traffic using AWS Network Firewall](https://aws.amazon.com/blogs/networking-and-content-delivery/securing-egress-using-aws-network-firewall/)
