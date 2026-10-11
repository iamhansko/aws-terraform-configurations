variable "name" {
  type        = string
  description = "Base name for the cache policy and the distribution's comment. A cache policy name is unique per account, so this is what keeps two copies of the project from colliding - the _monolithic template derived it from the stack name for the same reason"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]{1,100}$", var.name))
    error_message = "name must be 1-100 characters of letters, digits, hyphens and underscores - CloudFront's limit for a cache policy name."
  }
}
variable "origin_domain_name" {
  type        = string
  description = "Public DNS name of the instance running code-server. The instance's own name rather than an ALB: there is one origin and no health checking, which is what makes this a demo shape"

  validation {
    condition     = can(regex("^[a-z0-9.-]+$", var.origin_domain_name))
    error_message = "origin_domain_name must be a hostname without a scheme or path."
  }
}
variable "origin_port" {
  type        = number
  default     = 8000
  description = "Port code-server listens on, passed in from the module that configured it so the two cannot disagree (rules.md B-5)"

  validation {
    condition     = var.origin_port > 0 && var.origin_port <= 65535
    error_message = "origin_port must be a valid TCP port."
  }
}
variable "origin_request_policy_id" {
  type        = string
  description = "Managed origin request policy the behaviour uses. Looked up by name by the caller and passed in as an id, because the _monolithic template wrote the bare uuid 216adef6-5c7f-47e4-b989-5492eafa07d3 into the configuration - which tells a reader nothing about which policy it is"

  validation {
    condition     = can(regex("^[0-9a-f-]{36}$", var.origin_request_policy_id))
    error_message = "origin_request_policy_id must be a CloudFront policy id."
  }
}
variable "viewer_protocol_policy" {
  type        = string
  default     = "redirect-to-https"
  description = <<-DESC
    What CloudFront does with a plain HTTP request from a browser. redirect-to-https, where the _monolithic
    template used allow-all.

    It matters more here than on a static site: code-server has no authentication in front of it, so every
    request carries a session that is worth protecting in transit. The hop from the edge to the instance is
    still plain HTTP on port 8000 - code-server is configured with cert: false - so this secures the viewer
    half only.
  DESC

  validation {
    condition     = contains(["allow-all", "https-only", "redirect-to-https"], var.viewer_protocol_policy)
    error_message = "viewer_protocol_policy must be allow-all, https-only or redirect-to-https."
  }
}
variable "price_class" {
  type        = string
  default     = "PriceClass_200"
  description = "Which edge locations serve the distribution. The _monolithic template left this unset, which is PriceClass_All - every location including the most expensive, for a distribution one person uses"

  validation {
    condition     = contains(["PriceClass_All", "PriceClass_200", "PriceClass_100"], var.price_class)
    error_message = "price_class must be PriceClass_All, PriceClass_200 or PriceClass_100."
  }
}
variable "forwarded_headers" {
  type = list(string)
  default = [
    "Accept",
    "Accept-Charset",
    "Accept-Datetime",
    "Accept-Encoding",
    "Accept-Language",
    "Authorization",
    "Host",
    "Origin",
    "Referer",
  ]
  description = "Headers included in the cache key and forwarded to the origin, as the _monolithic template listed them. code-server is a single-page application that authenticates and negotiates a WebSocket, so Host, Origin and Authorization all have to reach it - a cache policy that drops them serves a login loop"

  validation {
    condition     = length(var.forwarded_headers) > 0
    error_message = "forwarded_headers must contain at least one header."
  }
}
variable "min_ttl" {
  type        = number
  default     = 1
  description = "Shortest time an object is cached, as the _monolithic template had it"

  validation {
    condition     = var.min_ttl >= 0
    error_message = "min_ttl must be zero or greater."
  }
}
variable "default_ttl" {
  type        = number
  default     = 86400
  description = "Default cache lifetime, one day as the _monolithic template had it. It applies only to responses the origin does not give its own cache headers, and code-server gives its own for anything worth caching"

  validation {
    condition     = var.default_ttl >= 0
    error_message = "default_ttl must be zero or greater."
  }
}
variable "max_ttl" {
  type        = number
  default     = 31536000
  description = "Longest time an object is cached, a year as the _monolithic template had it"

  validation {
    condition     = var.max_ttl >= 0
    error_message = "max_ttl must be zero or greater."
  }
  validation {
    condition     = var.max_ttl >= var.default_ttl
    error_message = "max_ttl must be greater than or equal to default_ttl - CloudFront rejects the combination rather than either value."
  }
}
variable "comment" {
  type        = string
  default     = null
  description = "Comment shown in the CloudFront console. Null derives one from name. The _monolithic template set none, which leaves a distribution whose purpose is nowhere recorded - and a console list of distributions identified only by their cloudfront.net names"

  validation {
    condition     = var.comment == null || length(var.comment) <= 128
    error_message = "comment must be 128 characters or fewer, or null to derive one."
  }
}
