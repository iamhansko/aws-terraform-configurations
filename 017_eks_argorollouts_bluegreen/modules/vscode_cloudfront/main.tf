# Puts CloudFront in front of the code-server instance so the browser reaches it
# over HTTPS on 443 with a CloudFront certificate, instead of opening the
# instance's port 8000 to the internet in plaintext. Pair this with the EC2
# security group allowing inbound only from the
# com.amazonaws.global.cloudfront.origin-facing managed prefix list, so the
# origin is unreachable except through the distribution.
# Suffix that makes the cache policy name unique in the account.
#
# Created unconditionally rather than under a count, so that the name expression below stays a plain
# conditional: a zero-instance resource cannot be indexed, and both branches of a conditional are evaluated.
# It holds no AWS resource, so the only cost is a line in state.
resource "random_id" "cache_policy_suffix" {
  byte_length = 4
}
locals {
  # Generated unless the caller pinned a name. Nothing reads this policy by name - the distribution below
  # references its id - so there is nothing for a predictable name to buy, while an account-unique namespace
  # makes a fixed one collide (rules.md G-3).
  cache_policy_name = var.cache_policy_name != null ? var.cache_policy_name : "${var.cache_policy_name_prefix}-${random_id.cache_policy_suffix.hex}"
}
resource "aws_cloudfront_cache_policy" "vscode_cache_policy" {
  name        = local.cache_policy_name
  comment     = "Forwards the headers, cookies and query strings code-server needs, including its websocket upgrade"
  default_ttl = var.default_ttl
  min_ttl     = var.min_ttl
  max_ttl     = var.max_ttl
  parameters_in_cache_key_and_forwarded_to_origin {
    enable_accept_encoding_gzip = false
    cookies_config {
      # code-server tracks session state in cookies, so they have to reach the
      # origin rather than being stripped at the edge.
      cookie_behavior = "all"
    }
    headers_config {
      header_behavior = "whitelist"
      headers {
        items = var.forwarded_headers
      }
    }
    query_strings_config {
      query_string_behavior = "all"
    }
  }
}
resource "aws_cloudfront_distribution" "vscode_distribution" {
  enabled         = true
  comment         = var.comment
  price_class     = var.price_class
  is_ipv6_enabled = true

  origin {
    domain_name = var.origin_domain_name
    origin_id   = var.origin_domain_name
    custom_origin_config {
      # code-server is reached over plain HTTP on its own port; TLS terminates
      # at CloudFront. http_port therefore has to match the port code-server
      # actually binds to, which is why it is passed in rather than hardcoded.
      http_port              = var.origin_http_port
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id = var.origin_domain_name
    # code-server is an interactive editor, so every method has to pass through,
    # not just the cacheable ones.
    allowed_methods = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods  = ["GET", "HEAD"]
    compress        = false
    # allow-all rather than redirect-to-https so the distribution also answers
    # plain HTTP, matching the _monolithic template's behaviour.
    viewer_protocol_policy = var.viewer_protocol_policy
    cache_policy_id        = aws_cloudfront_cache_policy.vscode_cache_policy.id
    # AWS managed "AllViewer" origin request policy: passes every viewer header,
    # cookie and query string to the origin, which code-server's websocket
    # handshake needs.
    origin_request_policy_id = var.origin_request_policy_id
  }

  restrictions {
    geo_restriction {
      restriction_type = length(var.geo_restriction_locations) > 0 ? var.geo_restriction_type : "none"
      locations        = length(var.geo_restriction_locations) > 0 ? var.geo_restriction_locations : null
    }
  }

  viewer_certificate {
    # Uses the default *.cloudfront.net certificate, so no custom domain or ACM
    # certificate is needed for a demo.
    cloudfront_default_certificate = true
  }
}
