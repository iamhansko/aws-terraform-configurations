variable "comment" {
  type        = string
  default     = "CloudFront Distribution"
  description = "Comment shown in the CloudFront console, as the _monolithic template had it. The only place a distribution's purpose can be written - it has no Name tag that the console lists"

  validation {
    condition     = length(var.comment) > 0 && length(var.comment) <= 128
    error_message = "comment must be 1-128 characters - CloudFront's own limit."
  }
}
variable "origin_domain_name" {
  type        = string
  description = "Hostname of the origin. The S3 website endpoint, which is a custom origin rather than an S3 origin - see main.tf for why that distinction matters"

  validation {
    condition     = can(regex("^[a-z0-9.-]+$", var.origin_domain_name))
    error_message = "origin_domain_name must be a hostname without a scheme or path."
  }
}
variable "default_root_object" {
  type        = string
  default     = "index.html"
  description = "Object CloudFront requests when the path is /. Passed in from the bucket module so it is the same key the website endpoint serves for a directory (rules.md B-5). Note that this applies only to the root: /docs/ is resolved by the website endpoint, not here, which is the whole reason for that origin type"

  validation {
    condition     = can(regex("^[^/][^\\s]*$", var.default_root_object))
    error_message = "default_root_object must be a key without a leading slash."
  }
}
variable "origin_custom_headers" {
  type        = map(string)
  default     = {}
  sensitive   = true
  description = "Headers CloudFront adds to every request it sends to the origin. Used here to carry the Referer secret the bucket policy requires, which is what keeps the public website endpoint from being useful to anyone who finds it. Marked sensitive because that is what it holds"
}
variable "viewer_protocol_policy" {
  type        = string
  default     = "redirect-to-https"
  description = "What CloudFront does with an HTTP request from a viewer. redirect-to-https, where the _monolithic template used allow-all: the origin is HTTP-only because a website endpoint cannot do otherwise, but there is no reason for the viewer half to be, and allow-all means a site that silently works over plain HTTP"

  validation {
    condition     = contains(["allow-all", "https-only", "redirect-to-https"], var.viewer_protocol_policy)
    error_message = "viewer_protocol_policy must be allow-all, https-only or redirect-to-https."
  }
}
variable "cache_policy_id" {
  type        = string
  description = "Managed cache policy the default behaviour uses. A policy rather than the forwarded_values block the _monolithic template used: that block is the legacy form, and CloudFront's own documentation directs new distributions at policies. The caller passes the id of a managed policy looked up by name, so the name appears in the configuration rather than a bare uuid"

  validation {
    condition     = can(regex("^[0-9a-f-]{36}$", var.cache_policy_id))
    error_message = "cache_policy_id must be a CloudFront policy id."
  }
}
variable "allowed_methods" {
  type        = list(string)
  default     = ["GET", "HEAD"]
  description = "Methods CloudFront forwards, as the _monolithic template had them. A static site needs no more, and forwarding more than the origin can serve turns a 405 from S3 into a cached error"

  validation {
    condition     = length(setsubtract(var.allowed_methods, ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"])) == 0
    error_message = "allowed_methods must be drawn from GET, HEAD, OPTIONS, PUT, POST, PATCH and DELETE."
  }
}
variable "price_class" {
  type        = string
  default     = "PriceClass_200"
  description = "Which edge locations serve the distribution. The _monolithic template left this unset, which means PriceClass_All - every location, including the most expensive ones. 200 covers everything except South America and Oceania and is the usual choice for a demo"

  validation {
    condition     = contains(["PriceClass_All", "PriceClass_200", "PriceClass_100"], var.price_class)
    error_message = "price_class must be PriceClass_All, PriceClass_200 or PriceClass_100."
  }
}
variable "origin_ssl_protocols" {
  type        = list(string)
  default     = ["TLSv1.2"]
  description = "TLS versions CloudFront would use to reach the origin. Required by the provider even though it is unused here: origin_protocol_policy is http-only, because an S3 website endpoint does not serve HTTPS at all. The _monolithic template carried a generated comment saying the same thing"

  validation {
    condition     = length(setsubtract(var.origin_ssl_protocols, ["SSLv3", "TLSv1", "TLSv1.1", "TLSv1.2"])) == 0
    error_message = "origin_ssl_protocols must be drawn from SSLv3, TLSv1, TLSv1.1 and TLSv1.2."
  }
}
variable "geo_restriction_type" {
  type        = string
  default     = "none"
  description = "Whether viewers are restricted by country, none as the _monolithic template had it"

  validation {
    condition     = contains(["none", "whitelist", "blacklist"], var.geo_restriction_type)
    error_message = "geo_restriction_type must be none, whitelist or blacklist."
  }
}
variable "geo_restriction_locations" {
  type        = list(string)
  default     = []
  description = "Country codes the restriction applies to. Empty with a type of none"

  validation {
    condition     = alltrue([for code in var.geo_restriction_locations : can(regex("^[A-Z]{2}$", code))])
    error_message = "geo_restriction_locations must be two-letter uppercase country codes."
  }
  validation {
    # The pair is what can be wrong, not either value alone (rules.md B-1). CloudFront rejects a whitelist
    # or blacklist with no countries in it, and rejects countries with a type of none.
    condition     = var.geo_restriction_type == "none" ? length(var.geo_restriction_locations) == 0 : length(var.geo_restriction_locations) > 0
    error_message = "geo_restriction_locations must be empty when geo_restriction_type is none, and must name at least one country otherwise."
  }
}
