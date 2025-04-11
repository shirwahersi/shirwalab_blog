variable "envtype" {
  type    = string
  default = "shirwalab"
}

variable "envname" {
  type    = string
  default = "shirwalab"
}

variable "project" {
  type    = string
  default = "blog"
}


variable "region" {
  type = string
  #MOD_HOOK_IGNORE_MATCH
  default = "eu-west-2"
}

variable "bucket_name" {
  type    = string
  default = "shirwalab-blog"
}

variable "hosted_zone" {
  type    = string
  default = "shirwalab.net"
}