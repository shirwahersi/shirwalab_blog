+++
title = 'AWS Private Link Cross Region Connectivity lab'
date = 2025-04-26T12:34:29+01:00
tags = ['Home Lab', 'AWS', 'VPC Endpoint']
draft = false
+++


## Overview

AWS PrivateLink is a highly available, scalable technology that you can use to privately connect your VPC to services and resources as if they were within your VPC. You do not need to use an internet gateway, NAT device, public IP address, AWS Direct Connect connection, or AWS Site-to-Site VPN connection to allow communication with the service or resource from your private subnets. Therefore, you control the specific API endpoints, sites, services, and resources that are reachable from your VPC.

Until the end of November 2024, Interface VPC endpoints only supported connectivity to VPC endpoint services in the same region. AWS [launched](https://aws.amazon.com/blogs/networking-and-content-delivery/introducing-cross-region-connectivity-for-aws-privatelink/) support for cross-region connectivity on November 26, 2024.

## Cross-Region Architecture

### Before Cross-Region Connectivity:

Before the launch of cross-region connectivity, consumers who wanted to access a service in another region had to set up inter-region VPC peering or Transit Gateway (TGW) peering. This setup required ensuring that their networks did not have overlapping CIDRs and establishing guardrails to secure the network trust boundary. These configurations were complex and required careful planning to maintain security and connectivity.

![Cross-Region Before ](/static/images/private-link/vpce-before.png)

### After Cross-Region Connectivity:

With the introduction of cross-region connectivity, AWS PrivateLink abstracts away all this complexity and offers a simple, native cross-region connectivity experience for consumers and providers. Providers can simply enable cross-region connectivity to allow consumers from any region to access their services. Consumers can then use endpoints to connect to these remote services just as they connect to in-region services today. This streamlined approach significantly reduces the operational overhead and simplifies the network architecture.

![Cross-Region After ](/static/images/private-link/vpce-after.png)

## AWS Private Link Cross Region Connectivity Lab

### Lab overview

In this lab, we will demonstrate AWS multi-region PrivateLink using two AWS accounts:

**Producer Account:** This account has a web service running Nginx in the AWS region us-east-1.

**Consumer Account:** This account is located in the eu-west-2 region. The consumer account will establish a PrivateLink connection from eu-west-2 using `aws_vpc_endpoint` to `aws_vpc_endpoint_service` service hosted in the Producer account located in us-east-1.

We will also test connectivity from the Consumer account by connecting to the Nginx host hosted in Producer account via a PrivateLink without going through the internet.

![Private Link multi-region ](/static/images/private-link/privatelink-multiregion1.png)

### Objectives

* Understand the concept of AWS PrivateLink and its benefits.
* Set up cross-region connectivity using AWS PrivateLink.
* Verify the connectivity between VPCs in different regions.

### Prerequisites

* AWS Accounts: Two AWS accounts.
  * One account for the Producer (us-east-1).
  * One account for the Consumer (eu-west-2).
* VPCs: Two VPCs in different regions.
  * VPC 1 in US East (N. Virginia).
  * VPC 2 in EU West (London).
* IAM permission

> Opt into cross-region [PrivateLink connectivity](http://localhost:1313/posts/aws-private-link-cross-region-connectivity/): While all PrivateLink actions so far were included in the ec2 namespace, cross-region actions are gated behind the new `vpce:AllowMultiRegion` permission-only action. Without opting into this permission, you will retain undisrupted in-region PrivateLink connectivity but sharing or accessing services across regions will fail.

## Lab Steps

### Step 1: Setup terraform credentials

This configuration defines two instances of the AWS provider, one for the source and one for the destination profile in your ~/.aws/credentials file. The provider alias allows Terraform to differentiate the two AWS providers.

```
# file: providers.tf
provider "aws" {
  alias   = "producer_account"
  profile = "producer_account"
  region  = "us-east-1"
  default_tags {
    tags = local.envname_tags
  }
}

provider "aws" {
  alias   = "consumer_account"
  profile = "consumer_account"
  region  = "eu-west-2"
  default_tags {
    tags = local.envname_tags
  }
}
```

### Step 2: Setup locals containing global configuration

```
locals {
  envname_tags = {
    stack = "shirwalab-multi-region-private-link"
  }

  producer_cidr            = "10.0.0.0/16"
  producer_azs             = ["us-east-1a", "us-east-1b", "us-east-1c"]
  producer_private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  producer_public_subnets  = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]

  consumer_cidr            = "172.16.0.0/16"
  consumer_azs             = ["eu-west-2a", "eu-west-2b", "eu-west-2c"]
  consumer_private_subnets = ["172.16.1.0/24", "172.16.2.0/24", "172.16.3.0/24"]
  consumer_public_subnets  = ["172.16.4.0/24", "172.16.5.0/24", "172.16.6.0/24"]

  private_link_supported_regions = [
    "us-east-1",
    "eu-west-2",
  ]
}
```

### Step 3: Create VPCs and Subnets in Producer account


```
module "producer_account_vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "v5.21.0"

  providers = {
    aws = aws.producer_account
  }

  name = "shirwalab-producer-account-vpc"
  cidr = local.producer_cidr

  azs             = local.producer_azs
  private_subnets = local.producer_private_subnets
  public_subnets  = local.producer_public_subnets

  enable_nat_gateway     = true
  single_nat_gateway     = true
  one_nat_gateway_per_az = false
}
```

### Step 4: Create nginx ec2 instance with Network Loadbalancer (NLB)


```
# file: producer_account.tf

locals {
  user_data = <<-EOT
    #!/bin/bash
    yum update -y
    yum install -y httpd
    systemctl start httpd
    systemctl enable httpd
    echo "<h1>Hello from the web server running on producer AWS account!</h1>" > /var/www/html/index.html
  EOT
}

resource "aws_security_group" "web_sg" {
  provider = aws.producer_account

  name        = "web-sg"
  description = "Allow HTTP and SSH access"
  vpc_id      = module.producer_account_vpc.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [module.producer_account_vpc.vpc_cidr_block]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [module.producer_account_vpc.vpc_cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "nlb_sg" {
  provider = aws.producer_account

  name        = "nlb-sg"
  description = "Allow HTTP"
  vpc_id      = module.producer_account_vpc.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [module.producer_account_vpc.vpc_cidr_block]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [local.consumer_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_launch_template" "this" {
  provider = aws.producer_account

  name_prefix            = "shirwalab-producer-account-launch-template"
  image_id               = data.aws_ami.al2023.id
  instance_type          = "t3.micro"
  key_name               = "shirwa"
  user_data              = base64encode(local.user_data)
  vpc_security_group_ids = [aws_security_group.web_sg.id]
  lifecycle {
    create_before_destroy = true
  }
}


resource "aws_autoscaling_group" "asg" {
  provider            = aws.producer_account
  desired_capacity    = 1
  max_size            = 1
  min_size            = 1
  vpc_zone_identifier = module.producer_account_vpc.private_subnets
  launch_template {
    id      = aws_launch_template.this.id
    version = "$Latest"
  }
}

resource "aws_lb" "nlb" {
  provider                         = aws.producer_account
  name                             = "shirwalab-vpce-nlb"
  internal                         = true
  load_balancer_type               = "network"
  subnets                          = module.producer_account_vpc.private_subnets
  security_groups                  = [aws_security_group.nlb_sg.id]
  enable_cross_zone_load_balancing = true
}

resource "aws_lb_target_group" "nginx-tg" {
  provider = aws.producer_account

  name        = "nginx-tg"
  port        = 80
  protocol    = "TCP"
  vpc_id      = module.producer_account_vpc.vpc_id
  target_type = "instance"
}

resource "aws_lb_listener" "listener" {
  provider = aws.producer_account

  load_balancer_arn = aws_lb.nlb.arn
  port              = 80
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.nginx-tg.arn
  }
}

resource "aws_autoscaling_attachment" "example" {
  provider               = aws.producer_account
  autoscaling_group_name = aws_autoscaling_group.asg.id
  lb_target_group_arn    = aws_lb_target_group.nginx-tg.arn
}
```

### Step 5: Create VPC Endpoint Service

To enable multi-region support, set the `supported_regions` parameter to the regions where service consumers can access the service. By default, this is the current region specified in the Terraform AWS provider. In our case, we will support two regions: `us-east-1` and `eu-west-2`.

Additionally, set the `allowed_principals` parameter to the ARNs of one or more principals allowed to discover the endpoint service. In our case, this will be the Consumer account ID.

```
resource "aws_vpc_endpoint_service" "endpoint_service" {
  provider                   = aws.producer_account
  acceptance_required        = false
  network_load_balancer_arns = [aws_lb.nlb.arn]
  supported_regions          = local.private_link_supported_regions
  allowed_principals         = ["arn:aws:iam::414336264239:root"]
  supported_ip_address_types = ["ipv4"]
  tags                       = { Name = "shirwalab-producer-account-vpce" }
}
```

### Step 6: Create VPCs and Subnets in Consumer account

```
# file: consumer_account.tf

module "consumer_account_vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "v5.21.0"

  providers = {
    aws = aws.consumer_account
  }

  name                   = "shirwalab-consumer-account-vpc"
  cidr                   = local.consumer_cidr
  azs                    = local.consumer_azs
  private_subnets        = local.consumer_private_subnets
  public_subnets         = local.consumer_public_subnets
  enable_nat_gateway     = true
  single_nat_gateway     = true
  one_nat_gateway_per_az = false
}
```

### Step 7: Create Interface VPC Endpoint

In Consumer account VPC 2, create an interface VPC endpoint and security group.

```
resource "aws_security_group" "consumer_vpce_sg" {
  provider = aws.consumer_account

  name        = "consumer_vpce_sg"
  description = "Allow HTTP and SSH access"
  vpc_id      = module.consumer_account_vpc.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [module.consumer_account_vpc.vpc_cidr_block]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [module.consumer_account_vpc.vpc_cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_vpc_endpoint" "consumer_vpc_endpoints" {
  provider = aws.consumer_account

  vpc_id              = module.consumer_account_vpc.vpc_id
  vpc_endpoint_type   = "Interface"
  service_name        = aws_vpc_endpoint_service.endpoint_service.service_name
  subnet_ids          = module.consumer_account_vpc.private_subnets
  security_group_ids  = [aws_security_group.consumer_vpce_sg.id]
  service_region      = "us-east-1"
  private_dns_enabled = false

  tags = {
    Name = "shirwalab-consumer-vpc-endpoint"
  }
}
```

When configuring the VPC endpoint, you also need to specify the region where the service is hosted. In our case, it's hosted in us-east-1.

### Step 8: Verify Connectivity

Once the endpoint is created and enters ‘Available’ state, cross-region connectivity can be successfully established. You can see the configuration details as below.

![vpc endpoint ](/static/images/private-link/private-link-lab1.png)

Notice that there are multiple endpoint DNS names generated. The first DNS entry is the regional DNS name, followed by an entry for each endpoint AZ’s DNS name. This example used two AZs so there are a total of three DNS names. Using the regional DNS name for your application is recommended for better availability and resiliency. You can also enable Private DNS names on the endpoint to use a custom name to access the provider’s services. For more information in Private DNS, Subnets and AZs, see refer to section in the AWS PrivateLink User Guide.

To test connectivity, create an EC2 instance in the Consumer VPC and try to connect to the regional endpoint DNS name. As shown below, we were able to connect successfully from the Consumer VPC to the Nginx instance hosted in the Producer account using PrivateLink, without going through the internet across different regions.

```
$ curl vpce-037ac5ae30dee74b7-fyt7nl9r.vpce-svc-018027fbc1f926e4c.us-east-1.vpce.amazonaws.com
<h1>Hello from the web server running on producer AWS account!</h1>
```

## Additional Information

Repository: The complete Terraform code for this lab can be found in the AWS PrivateLink Cross-Region Lab repository - https://github.com/shirwahersi/aws-privatelink-cross-region-lab

## Resources

* https://aws.amazon.com/blogs/networking-and-content-delivery/introducing-cross-region-connectivity-for-aws-privatelink/
