resource "aws_s3_bucket" "blog" {
  #checkov:skip=CKV2_AWS_62:Notification is not required
  #checkov:skip=CKV2_AWS_61:Disable lifecycle
  #checkov:skip=CKV_AWS_18:Disable Access loggigng
  #checkov:skip=CKV_AWS_144:Disable cross region repli
  #checkov:skip=CKV_AWS_21:Disable versioning
  #checkov:skip=CKV_AWS_145:Disable KMS
  bucket = var.bucket_name
}

data "aws_cloudfront_response_headers_policy" "blog" {
  name = "Managed-CORS-and-SecurityHeadersPolicy"
}

data "aws_cloudfront_cache_policy" "hugo_cache" {
  name = "Managed-CachingOptimized"
}

resource "aws_s3_bucket_public_access_block" "blog" {
  bucket                  = aws_s3_bucket.blog.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "aws_iam_policy_document" "s3_policy" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.blog.arn}/*"]

    principals {
      type        = "AWS"
      identifiers = [aws_cloudfront_origin_access_identity.origin_access_identity.iam_arn]
    }
  }

  statement {
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.blog.arn]

    principals {
      type        = "AWS"
      identifiers = [aws_cloudfront_origin_access_identity.origin_access_identity.iam_arn]
    }
  }
}

resource "aws_acm_certificate" "blog" {
  provider                  = aws.global
  domain_name               = "shirwalab.net"
  subject_alternative_names = ["www.shirwalab.net", "blog.shirwalab.net"]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_s3_bucket_policy" "website_bucket_policy" {
  bucket = aws_s3_bucket.blog.id
  policy = data.aws_iam_policy_document.s3_policy.json
}

resource "aws_route53_record" "blog" {
  provider = aws.global
  for_each = {
    for dvo in aws_acm_certificate.blog.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.zone_id.zone_id
}

resource "aws_acm_certificate_validation" "blog" {
  provider                = aws.global
  certificate_arn         = aws_acm_certificate.blog.arn
  validation_record_fqdns = [for record in aws_route53_record.blog : record.fqdn]
}

resource "aws_cloudfront_origin_access_identity" "origin_access_identity" {
  comment = "origin access identity for s3/cloudfront"
}

resource "aws_cloudfront_function" "hugo-redirect" {
  name    = "${var.project}-hugo"
  runtime = "cloudfront-js-2.0"
  comment = "${var.project}-hugo"
  publish = true
  code    = file("${path.module}/function.js")
}

resource "aws_cloudfront_distribution" "s3_distribution" {
  #checkov:skip=CKV_AWS_86
  #checkov:skip=CKV_AWS_310
  #checkov:skip=CKV_AWS_68
  #checkov:skip=CKV2_AWS_47
  depends_on = [
    aws_s3_bucket.blog,
    aws_acm_certificate_validation.blog,
  ]

  origin {
    domain_name = aws_s3_bucket.blog.bucket_regional_domain_name
    origin_id   = aws_cloudfront_origin_access_identity.origin_access_identity.id

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.origin_access_identity.cloudfront_access_identity_path
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  aliases             = [aws_acm_certificate.blog.domain_name]

  default_cache_behavior {
    response_headers_policy_id = data.aws_cloudfront_response_headers_policy.blog.id
    cache_policy_id            = data.aws_cloudfront_cache_policy.hugo_cache.id

    allowed_methods = [
      "DELETE",
      "GET",
      "HEAD",
      "OPTIONS",
      "PATCH",
      "POST",
      "PUT",
    ]

    cached_methods = [
      "GET",
      "HEAD",
    ]

    target_origin_id = aws_cloudfront_origin_access_identity.origin_access_identity.id

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.hugo-redirect.arn
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 0
    max_ttl                = 0
  }

  price_class  = "PriceClass_100"
  http_version = "http2and3"

  viewer_certificate {
    cloudfront_default_certificate = false
    minimum_protocol_version       = "TLSv1.2_2018"
    acm_certificate_arn            = aws_acm_certificate.blog.arn
    ssl_support_method             = "sni-only"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
}

resource "aws_route53_record" "blog_cf" {
  name    = "shirwalab.net"
  type    = "A"
  zone_id = data.aws_route53_zone.zone_id.zone_id

  alias {
    name                   = aws_cloudfront_distribution.s3_distribution.domain_name
    zone_id                = aws_cloudfront_distribution.s3_distribution.hosted_zone_id
    evaluate_target_health = false
  }
}