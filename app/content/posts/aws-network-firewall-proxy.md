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

### 3. Deploy Infrastructure with Terraform

```bash
terraform init
terraform plan
terraform apply
```

### 4. Create Proxy Rule Group

The proxy rule group defines which domains are allowed or blocked:

```bash
aws network-firewall create-proxy-rule-group \
  --proxy-rule-group-name web-domain-filter \
  --description "egress domain filter" \
  --rules file://files/rules.json \
  --region us-east-2
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

### 6. Retrieve NAT Gateway ID

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

First, retrieve the VPC Endpoint Service Name:

```bash
aws network-firewall describe-proxy \
  --proxy-name "nfw-proxy" \
  --query "Proxy.VpcEndpointServiceName" \
  --output text --region us-east-2
```

Then create the VPC Endpoint via the AWS Console:

1. Navigate to VPC > Endpoints
2. Click "Create endpoint"
3. Select the service name from the previous command
4. Select APPVPC private subnets
5. Attach the `vpc-endpoint-app-vpc-sg` security group
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
curl -I https://www.google.com
curl -I https://www.bbc.co.uk
```

These should return `HTTP/1.1 200 OK` (or a redirect status).

### Test Blocked Domains

Verify that blocked domains are filtered:

```bash
curl -I https://www.facebook.com
curl -I https://www.github.com
```

These should return `HTTP/1.1 403 Forbidden`.

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

## Technical Notes

* As of January 23, 2026, this feature is in **preview** and only available in us-east-2
* Proxy resources must be created via AWS CLI as Terraform support is not yet available
* TLS interception is set to DISABLED in this lab; enable it for deeper inspection if required
* The `PreDNS=DENY` default action blocks all domains not explicitly allowed in the rule group

## References

* [AWS Network Firewall Proxy Lab Repository](https://github.com/shirwahersi/aws-network-firewall-proxy-lab)
* [Deployment models for AWS Network Firewall](https://docs.aws.amazon.com/network-firewall/latest/developerguide/architectures.html)
* [Securing egress traffic using AWS Network Firewall](https://aws.amazon.com/blogs/networking-and-content-delivery/securing-egress-using-aws-network-firewall/)
