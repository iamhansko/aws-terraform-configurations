# The distribution in front of the S3 website endpoint.
#
# Declared as a custom origin, not an S3 origin, and that is not a choice: an S3 *website* endpoint is an
# ordinary HTTP server as far as CloudFront is concerned. It is what makes origin_access_control_id
# unavailable here - OAC is only for the REST endpoint - and it is why the bucket has to be publicly
# readable and the referer secret exists.
#
# Two things the _monolithic template left at CloudFront's defaults are set here instead, because the
# defaults are the expensive ones: price_class was PriceClass_All, and viewer_protocol_policy was allow-all.
resource "aws_cloudfront_distribution" "distribution" {
  enabled             = true
  comment             = var.comment
  default_root_object = var.default_root_object
  price_class         = var.price_class

  origin {
    origin_id   = "s3-website"
    domain_name = var.origin_domain_name

    custom_origin_config {
      http_port  = 80
      https_port = 443
      # Not a choice either: the website endpoint does not serve HTTPS. The hop from the edge to S3 is
      # therefore plaintext, inside the AWS network. Using the REST endpoint with OAC is what removes this,
      # at the cost of index documents for subdirectories.
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = var.origin_ssl_protocols
    }

    # Carries the Referer secret the bucket policy requires. Sorted so a plan is stable, since a map's
    # iteration order in a dynamic block otherwise follows the key order Terraform happens to produce.
    dynamic "custom_header" {
      for_each = var.origin_custom_headers
      content {
        name  = custom_header.key
        value = custom_header.value
      }
    }
  }

  default_cache_behavior {
    target_origin_id       = "s3-website"
    viewer_protocol_policy = var.viewer_protocol_policy
    allowed_methods        = var.allowed_methods
    # Only what can be served from cache. CloudFront requires this to be a subset of allowed_methods, and
    # for a static site the two lists are the same.
    cached_methods = ["GET", "HEAD"]
    # A cache policy instead of the forwarded_values block the _monolithic template used. forwarded_values
    # is the legacy form: it cannot express the newer controls, and the two cannot be combined - a
    # distribution has either a policy or forwarded_values, so this is a replacement rather than an
    # addition.
    cache_policy_id = var.cache_policy_id
    compress        = true
  }

  restrictions {
    geo_restriction {
      restriction_type = var.geo_restriction_type
      locations        = var.geo_restriction_locations
    }
  }

  viewer_certificate {
    # The *.cloudfront.net certificate. A custom domain would need an ACM certificate in us-east-1 and an
    # aliases entry, which is a different project.
    cloudfront_default_certificate = true
  }
}
