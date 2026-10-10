# A distribution with two origins - an S3 bucket and the VS Code instance - and a viewer-request Lambda@Edge
# function on each behaviour.
#
# The bucket is here because its policy names this distribution and the distribution names the bucket's
# domain; split across modules, the two would each need the other's output.
resource "aws_s3_bucket" "origin" {
  bucket_prefix = var.bucket_prefix
  force_destroy = true
}
# Private, where the _monolithic template made it public: it turned every public access block setting off and
# granted s3:GetObject to Principal "*", and pointed CloudFront at it with no origin access control - so the
# bucket was readable straight from S3 by anyone, bypassing the distribution and its Lambda@Edge function. CloudFront
# reads it through the origin access control below instead, and nothing a viewer sees changes.
resource "aws_s3_bucket_public_access_block" "origin" {
  bucket                  = aws_s3_bucket.origin.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
resource "aws_s3_bucket_ownership_controls" "origin" {
  bucket = aws_s3_bucket.origin.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}
# The page the _monolithic template's userdata wrote with echo and uploaded with aws s3 cp - after the
# instance was running, so the distribution existed for minutes with nothing behind its default root object.
resource "aws_s3_object" "index" {
  bucket       = aws_s3_bucket.origin.id
  key          = var.default_root_object
  content      = var.index_html
  content_type = "text/html"
  depends_on   = [aws_s3_bucket_ownership_controls.origin]
}
resource "aws_cloudfront_origin_access_control" "origin" {
  name                              = "${aws_s3_bucket.origin.id}-oac"
  description                       = "CloudFront access to ${aws_s3_bucket.origin.id}"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}
resource "aws_s3_bucket_policy" "origin" {
  bucket = aws_s3_bucket.origin.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "CloudFrontReadThroughThisDistributionOnly"
      Effect    = "Allow"
      Principal = { Service = "cloudfront.amazonaws.com" }
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.origin.arn}/*"
      Condition = {
        StringEquals = { "AWS:SourceArn" = aws_cloudfront_distribution.distribution.arn }
      }
    }]
  })
  # S3 checks a new policy against the public access block in a separate call (rules.md D-1).
  depends_on = [aws_s3_bucket_public_access_block.origin]
}
locals {
  s3_origin_id  = "S3Origin"
  ec2_origin_id = "Ec2Origin"
  # "<prefix>" and "<prefix>/*", the two path patterns the _monolithic template routed to the instance: the
  # first is what nginx redirects to the trailing-slash form, the second is everything under it.
  ec2_path_patterns = [var.ec2_path_prefix, "${var.ec2_path_prefix}/*"]
}
resource "aws_cloudfront_distribution" "distribution" {
  enabled             = true
  comment             = var.comment
  default_root_object = var.default_root_object
  price_class         = var.price_class
  origin {
    origin_id                = local.s3_origin_id
    domain_name              = aws_s3_bucket.origin.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.origin.id
  }
  origin {
    origin_id   = local.ec2_origin_id
    domain_name = var.ec2_origin_domain_name
    custom_origin_config {
      http_port              = var.ec2_origin_http_port
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }
  default_cache_behavior {
    target_origin_id       = local.s3_origin_id
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    cache_policy_id        = var.cache_policy_id
    # A qualified ARN - a published version, not $LATEST - in us-east-1. CloudFront replicates exactly that
    # version to its edge locations; an unqualified ARN or one in another region is rejected.
    lambda_function_association {
      event_type   = "viewer-request"
      lambda_arn   = var.s3_origin_lambda_arn
      include_body = false
    }
  }
  dynamic "ordered_cache_behavior" {
    for_each = local.ec2_path_patterns
    content {
      path_pattern             = ordered_cache_behavior.value
      target_origin_id         = local.ec2_origin_id
      compress                 = true
      viewer_protocol_policy   = "redirect-to-https"
      allowed_methods          = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
      cached_methods           = ["GET", "HEAD"]
      cache_policy_id          = var.cache_policy_id
      origin_request_policy_id = var.origin_request_policy_id
      lambda_function_association {
        event_type   = "viewer-request"
        lambda_arn   = var.ec2_origin_lambda_arn
        include_body = false
      }
    }
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
