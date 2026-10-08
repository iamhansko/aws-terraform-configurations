variable "aws_region" {
  type        = string
  default     = null
  description = "Target AWS region. When null, falls back to the provider default chain (AWS_REGION, profile, etc.). It decides where the bucket lives; the distribution itself is global"

  validation {
    condition     = var.aws_region == null || can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]$", var.aws_region))
    error_message = "aws_region must be a valid AWS region such as ap-northeast-2, or null to fall back to the provider default chain."
  }
}
variable "project_name" {
  type        = string
  default     = "cloudfront-s3-website"
  description = "Base name for the bucket prefix and the distribution comment. One value rather than a name per resource, so a second copy of this project does not collide - and bucket names are globally unique, so this is the one that matters"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,38}$", var.project_name))
    error_message = "project_name must be 2-39 characters of lowercase letters, digits and hyphens, leaving room for the generated bucket suffix."
  }
}
variable "index_document" {
  type        = string
  default     = "index.html"
  description = "The site's entry document, as the _monolithic template had it. One value feeds three places that have to agree: the website configuration's index suffix, the distribution's default root object, and the key the content below is written to (rules.md B-5)"

  validation {
    condition     = can(regex("^[^/][^\\s]*\\.html?$", var.index_document))
    error_message = "index_document must be an .html or .htm key without a leading slash."
  }
}
variable "error_document" {
  type        = string
  default     = "error.html"
  description = "Document the website endpoint serves for a 4xx. The _monolithic template set none, so a missing key returned the endpoint's own XML error page through CloudFront - which is a confusing thing to see in a browser. Set null to get that behaviour back"

  validation {
    condition     = var.error_document == null || can(regex("^[^/][^\\s]*\\.html?$", var.error_document))
    error_message = "error_document must be an .html or .htm key without a leading slash, or null to leave it unset."
  }
}
variable "site_title" {
  type        = string
  default     = "CloudFront + S3 static website"
  description = "Heading in the generated pages. The content exists at all because the _monolithic template created an empty bucket: the distribution it built answered 404 to everything, so there was nothing to look at and no way to tell a working distribution from a broken one"

  validation {
    condition     = length(var.site_title) > 0
    error_message = "site_title must not be empty."
  }
}
variable "restrict_origin_to_cloudfront" {
  type        = bool
  default     = true
  description = <<-DESC
    Whether the bucket policy requires the secret Referer header the distribution sends, so that a direct
    request to the website endpoint is refused.

    True, where the _monolithic template's bucket was readable by anyone who knew the endpoint. It is worth
    being clear about how strong this is: not very. It is a shared secret in a request header, and anyone
    who learns it can use it. Origin Access Control is the real answer and cannot be used here, because it
    only works with the S3 REST endpoint and this project uses the website endpoint for its index-document
    behaviour.

    Set false to see what the original exposed: the direct_website_url output then serves the site with no
    CloudFront in front of it.
  DESC
}
variable "viewer_protocol_policy" {
  type        = string
  default     = "redirect-to-https"
  description = "What CloudFront does with a plain HTTP request from a browser. redirect-to-https, where the _monolithic template used allow-all. The origin hop is HTTP whatever this says, because an S3 website endpoint serves nothing else"

  validation {
    condition     = contains(["allow-all", "https-only", "redirect-to-https"], var.viewer_protocol_policy)
    error_message = "viewer_protocol_policy must be allow-all, https-only or redirect-to-https."
  }
}
variable "price_class" {
  type        = string
  default     = "PriceClass_200"
  description = "Which edge locations serve the distribution. The _monolithic template left it unset, which is PriceClass_All - every location including the most expensive"

  validation {
    condition     = contains(["PriceClass_All", "PriceClass_200", "PriceClass_100"], var.price_class)
    error_message = "price_class must be PriceClass_All, PriceClass_200 or PriceClass_100."
  }
}
variable "cache_policy_name" {
  type        = string
  default     = "Managed-CachingOptimized"
  description = "Managed cache policy the default behaviour uses, looked up by name so the configuration says which policy rather than carrying a bare uuid. CachingOptimized forwards no cookies, headers or query strings and compresses - the right shape for a static site, and what the _monolithic template's forwarded_values block was approximating"

  validation {
    condition     = can(regex("^Managed-", var.cache_policy_name))
    error_message = "cache_policy_name must name one of CloudFront's managed policies, which are all prefixed Managed-."
  }
}
