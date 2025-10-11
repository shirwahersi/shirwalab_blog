data "aws_route53_zone" "zone_id" {
  name         = var.hosted_zone
  private_zone = false
}

data "aws_secretsmanager_secret" "secrets" {
  name = "/${var.envname}/secrets"
}

data "aws_secretsmanager_secret_version" "secrets" {
  secret_id = data.aws_secretsmanager_secret.secrets.id
}