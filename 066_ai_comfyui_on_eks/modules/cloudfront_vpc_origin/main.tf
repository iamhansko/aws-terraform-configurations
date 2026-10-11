# The public entry point: a CloudFront distribution that reaches the internal ALB through a VPC origin.
#
# Replaces the blueprint's ComfyUI-on-EKS-CloudFront stack. That stack had to find the ALB with
# ApplicationLoadBalancer.fromLookup by the controller's tags, so it could only be deployed after the
# controller had built the ALB - which is why deploy_infra.sh ran it last, after waiting for the ComfyUI pod.
# Here the ALB is created by Terraform and adopted by the controller (rules.md G-3), so its ARN is an input
# like any other.
#
# The ALB stays internal and in private subnets. The VPC origin reaches it over CloudFront's own network
# interfaces in the VPC, and the ALB's security group admits CloudFront through the origin-facing managed
# prefix list - so nothing outside CloudFront can open a connection to it.
resource "aws_cloudfront_vpc_origin" "origin" {
  vpc_origin_endpoint_config {
    name                   = var.name
    arn                    = var.origin_arn
    http_port              = var.http_port
    https_port             = 443
    origin_protocol_policy = var.origin_protocol_policy
    origin_ssl_protocols {
      items    = ["TLSv1.2"]
      quantity = 1
    }
  }
}
resource "aws_cloudfront_distribution" "distribution" {
  enabled         = true
  is_ipv6_enabled = true
  comment         = "${var.name} - ComfyUI through a VPC origin"
  price_class     = var.price_class
  http_version    = "http2"

  origin {
    origin_id   = var.name
    domain_name = var.origin_domain_name

    vpc_origin_config {
      vpc_origin_id       = aws_cloudfront_vpc_origin.origin.id
      origin_read_timeout = var.origin_read_timeout
    }
  }

  default_cache_behavior {
    target_origin_id         = var.name
    viewer_protocol_policy   = "redirect-to-https"
    allowed_methods          = ["GET", "HEAD", "OPTIONS", "PUT", "PATCH", "POST", "DELETE"]
    cached_methods           = ["GET", "HEAD"]
    cache_policy_id          = var.cache_policy_id
    origin_request_policy_id = var.origin_request_policy_id
    compress                 = true
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}
