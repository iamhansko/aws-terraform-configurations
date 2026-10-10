# A private bucket behind a CloudFront distribution, read through an origin access control, and optionally a
# second origin for websocket traffic under one path. Called twice: the game client (the built single-page
# app, with the server's websocket under /ws*) and the generated item images.
#
# The bucket is here because its policy names this distribution and the distribution names the bucket's
# domain; split across modules, each would need the other's output.
resource "aws_s3_bucket" "origin" {
  bucket_prefix = var.bucket_prefix
  # Nothing in this bucket is Terraform's: the workbench uploads the client build into one and the item image
  # service writes into the other, so without this terraform destroy stops at BucketNotEmpty.
  force_destroy = true
}
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
resource "aws_cloudfront_origin_access_control" "origin" {
  name                              = var.origin_access_control_name
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}
resource "aws_s3_bucket_policy" "origin" {
  bucket = aws_s3_bucket.origin.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "cloudfront.amazonaws.com" }
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.origin.arn}/*"
      Condition = {
        StringEquals = { "AWS:SourceArn" = aws_cloudfront_distribution.distribution.arn }
        Bool         = { "aws:SecureTransport" = "true" }
      }
    }]
  })
  # S3 checks a new policy against the public access block in a separate call (rules.md D-1).
  depends_on = [aws_s3_bucket_public_access_block.origin]
}
locals {
  s3_origin_id        = "S3Origin"
  websocket_origin_id = "WebSocketOrigin"
}
resource "aws_cloudfront_distribution" "distribution" {
  enabled             = true
  comment             = var.comment
  default_root_object = var.default_root_object
  http_version        = "http3"
  price_class         = var.price_class
  origin {
    origin_id                = local.s3_origin_id
    domain_name              = aws_s3_bucket.origin.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.origin.id
  }
  dynamic "origin" {
    for_each = var.websocket_origin == null ? [] : [var.websocket_origin]
    content {
      origin_id   = local.websocket_origin_id
      domain_name = origin.value.domain_name
      custom_origin_config {
        http_port                = origin.value.http_port
        https_port               = 443
        origin_protocol_policy   = "http-only"
        origin_ssl_protocols     = ["TLSv1.2"]
        origin_keepalive_timeout = 15
      }
    }
  }
  default_cache_behavior {
    target_origin_id       = local.s3_origin_id
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = var.default_allowed_methods
    cached_methods         = var.default_allowed_methods
    compress               = true
    min_ttl                = 3600
    default_ttl            = 86400
    max_ttl                = 31536000
    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
  }
  dynamic "ordered_cache_behavior" {
    for_each = var.websocket_origin == null ? [] : [var.websocket_origin]
    content {
      path_pattern           = ordered_cache_behavior.value.path_pattern
      target_origin_id       = local.websocket_origin_id
      viewer_protocol_policy = "redirect-to-https"
      allowed_methods        = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
      cached_methods         = ["GET", "HEAD", "OPTIONS"]
      compress               = true
      # The websocket handshake headers, which CloudFront strips unless they are forwarded. Without them the
      # upgrade reaches the server as a plain GET and the game never connects.
      forwarded_values {
        query_string = true
        headers      = ordered_cache_behavior.value.forwarded_headers
        cookies {
          forward = "none"
        }
      }
    }
  }
  # A single-page app's routes are not objects in the bucket, so a deep link comes back 403 from S3 (or 404).
  # Answering both with index.html lets the app's router take over.
  dynamic "custom_error_response" {
    for_each = var.spa_fallback ? [403, 404] : []
    content {
      error_code         = custom_error_response.value
      response_code      = 200
      response_page_path = "/${var.default_root_object}"
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
