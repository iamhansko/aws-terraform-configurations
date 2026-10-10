# CloudFront in front of code-server on the workbench.
#
# The reason it exists is the security group: with this distribution, the instance's port 8000 is opened only
# to CloudFront's origin-facing prefix list rather than to 0.0.0.0/0, which is what most of the other projects
# in this repository do. So the workbench is reachable from a browser without being reachable from the
# internet at large.
#
# It is worth being precise about what that buys, because it is easy to overstate. code-server here runs with
# auth: none, and the distribution has no authentication of its own - no signed URLs, no Lambda@Edge, no WAF.
# Anyone with the cloudfront.net hostname has the IDE, and through it an instance holding AdministratorAccess.
# What the prefix list prevents is a port scan finding it directly; it does not make it private.
resource "aws_cloudfront_cache_policy" "code_server" {
  name        = "VSCode-${var.name}"
  comment     = "Cache policy for code-server behind CloudFront: forwards the headers, cookies and query strings a single-page application needs"
  min_ttl     = var.min_ttl
  default_ttl = var.default_ttl
  max_ttl     = var.max_ttl

  parameters_in_cache_key_and_forwarded_to_origin {
    # All of them, as the _monolithic template had it. code-server keeps its session in a cookie, so a policy
    # that drops cookies serves one user's session to the next.
    cookies_config {
      cookie_behavior = "all"
    }
    query_strings_config {
      query_string_behavior = "all"
    }
    headers_config {
      header_behavior = "whitelist"
      headers {
        items = var.forwarded_headers
      }
    }
    # Both false, which is what makes the whitelist above legal. Accept-Encoding is in forwarded_headers, as
    # the _monolithic template listed it, and CloudFront accepts that header in a whitelist only while both
    # flags are off - with either one on, CloudFront normalises Accept-Encoding into the cache key itself and
    # rejects a policy that also lists it. Brotli is stated rather than left to the provider default so that
    # turning it on reads as the change it is.
    enable_accept_encoding_gzip   = false
    enable_accept_encoding_brotli = false
  }
}
resource "aws_cloudfront_distribution" "code_server" {
  enabled     = true
  comment     = var.comment == null ? "code-server on ${var.name}" : var.comment
  price_class = var.price_class

  origin {
    origin_id   = "code-server"
    domain_name = var.origin_domain_name

    custom_origin_config {
      http_port  = var.origin_port
      https_port = 443
      # code-server is configured with cert: false, so the origin speaks HTTP only. The edge-to-origin hop is
      # therefore plaintext across the public internet - which is the part this shape does not fix, and the
      # reason a real deployment would put an ALB with a certificate here instead.
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id       = "code-server"
    viewer_protocol_policy = var.viewer_protocol_policy
    # Everything, because the IDE is an application rather than a document: saving a file is a POST and the
    # terminal is a WebSocket.
    allowed_methods = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods  = ["GET", "HEAD"]
    # A cache policy and an origin request policy, and no forwarded_values block.
    #
    # The _monolithic template set both forwarded_values and cache_policy_id on the same behaviour. They are
    # the legacy and the current way of saying the same thing and CloudFront accepts only one - so that
    # configuration was rejected at apply, with an error naming neither of them as the conflict.
    cache_policy_id          = aws_cloudfront_cache_policy.code_server.id
    origin_request_policy_id = var.origin_request_policy_id
    # False, as the original had it. code-server serves its own pre-compressed assets, and compressing an
    # already-compressed response costs CPU at the edge for nothing.
    compress = false
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    # The *.cloudfront.net certificate. A custom domain would need an ACM certificate in us-east-1 and an
    # aliases entry.
    cloudfront_default_certificate = true
  }
}
