provider "aws" {
  region = var.region

  default_tags {
    tags = local.envname_tags
  }
}

provider "aws" {
  alias  = "global"
  region = "us-east-1"

  default_tags {
    tags = local.envname_tags
  }
}