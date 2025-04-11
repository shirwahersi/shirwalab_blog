data "aws_route53_zone" "zone_id" {
  name         = var.hosted_zone
  private_zone = false
}
