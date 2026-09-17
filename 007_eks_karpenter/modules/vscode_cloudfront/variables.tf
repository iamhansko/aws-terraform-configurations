variable "origin_domain_name" {
  type        = string
  description = "Public DNS name of the instance running code-server, used as the custom origin. Pass the vscode_ec2 module's public_dns output rather than an IP, since a custom origin must be a domain name"

  validation {
    condition     = length(var.origin_domain_name) > 0 && !can(regex("^https?://", var.origin_domain_name))
    error_message = "origin_domain_name must be a bare domain name, without a scheme."
  }
}
variable "origin_http_port" {
  type        = number
  default     = 8000
  description = "Port the origin serves plain HTTP on. Pass the vscode_ec2 module's code_server_port output so the two cannot drift apart (rules.md B-5)"

  validation {
    condition     = var.origin_http_port > 0 && var.origin_http_port <= 65535
    error_message = "origin_http_port must be a valid TCP port."
  }
}
variable "cache_policy_name" {
  type        = string
  default     = "vscode-code-server"
  description = "Name of the cache policy created for the distribution. Must be unique within the account, so change it when deploying this project twice"

  validation {
    condition     = can(regex("^[0-9A-Za-z_-]{1,128}$", var.cache_policy_name))
    error_message = "cache_policy_name must contain only letters, digits, hyphens and underscores (128 characters or fewer)."
  }
}
variable "comment" {
  type        = string
  default     = "code-server on EC2"
  description = "Comment shown against the distribution in the CloudFront console"

  validation {
    condition     = length(var.comment) > 0 && length(var.comment) <= 128
    error_message = "comment must be between 1 and 128 characters."
  }
}
variable "price_class" {
  type        = string
  default     = "PriceClass_100"
  description = "Which CloudFront edge locations serve the distribution. PriceClass_100 is the cheapest and covers North America and Europe"

  validation {
    condition     = contains(["PriceClass_All", "PriceClass_200", "PriceClass_100"], var.price_class)
    error_message = "price_class must be one of: PriceClass_All, PriceClass_200, PriceClass_100."
  }
}
variable "viewer_protocol_policy" {
  type        = string
  default     = "allow-all"
  description = "How viewers may connect. redirect-to-https forces browsers onto TLS; allow-all also answers plain HTTP, which is what the _monolithic template did"

  validation {
    condition     = contains(["allow-all", "https-only", "redirect-to-https"], var.viewer_protocol_policy)
    error_message = "viewer_protocol_policy must be one of: allow-all, https-only, redirect-to-https."
  }
}
variable "origin_request_policy_id" {
  type        = string
  default     = "216adef6-5c7f-47e4-b989-5492eafa07d3"
  description = "Origin request policy ID. The default is the AWS managed AllViewer policy, which forwards every viewer header, cookie and query string to the origin - required for code-server's websocket upgrade to survive the edge"

  validation {
    condition     = can(regex("^[0-9a-f-]{36}$", var.origin_request_policy_id))
    error_message = "origin_request_policy_id must be a UUID."
  }
}
variable "min_ttl" {
  type        = number
  default     = 1
  description = "Minimum time CloudFront keeps an object before revalidating with the origin"

  validation {
    condition     = var.min_ttl >= 0
    error_message = "min_ttl must be zero or greater."
  }
}
variable "default_ttl" {
  type        = number
  default     = 86400
  description = "Default cache lifetime for responses without explicit cache headers"

  validation {
    condition     = var.default_ttl >= 0
    error_message = "default_ttl must be zero or greater."
  }
}
variable "max_ttl" {
  type        = number
  default     = 31536000
  description = "Upper bound on cache lifetime, regardless of origin cache headers"

  validation {
    condition     = var.max_ttl >= 0
    error_message = "max_ttl must be zero or greater."
  }
}
variable "forwarded_headers" {
  type = list(string)
  default = [
    "Accept", "Accept-Charset", "Accept-Datetime", "Accept-Encoding", "Accept-Language",
    "Authorization", "Host", "Origin", "Referer",
  ]
  description = "Viewer headers included in the cache key and forwarded to the origin"

  validation {
    condition     = length(var.forwarded_headers) > 0
    error_message = "forwarded_headers must contain at least one header name."
  }
}
variable "geo_restriction_type" {
  type        = string
  default     = "whitelist"
  description = "How geo_restriction_locations is interpreted. Ignored when that list is empty, in which case no geo restriction is applied"

  validation {
    condition     = contains(["whitelist", "blacklist"], var.geo_restriction_type)
    error_message = "geo_restriction_type must be either whitelist or blacklist."
  }
}
variable "geo_restriction_locations" {
  type        = list(string)
  default     = []
  description = "Two-letter country codes the geo restriction applies to. Setting this to the countries you actually work from is a cheap way to narrow who can reach an unauthenticated code-server. When empty, no restriction is applied"

  validation {
    condition     = alltrue([for code in var.geo_restriction_locations : can(regex("^[A-Z]{2}$", code))])
    error_message = "geo_restriction_locations must contain uppercase two-letter ISO country codes (e.g. KR)."
  }
}
