terraform {
  required_version = "~> 1.11.3"

  backend "s3" {}

  required_providers {
    # Provider Documentation: https://registry.terraform.io/providers/hashicorp/aws/latest
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.66.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "5.11.0"
    }
  }
}