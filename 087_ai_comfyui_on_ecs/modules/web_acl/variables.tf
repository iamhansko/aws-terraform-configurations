variable "name" {
  type        = string
  description = "Name of the web ACL, and the prefix of its IP sets"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,120}$", var.name))
    error_message = "name must be 1-120 letters, digits, hyphens and underscores - WAF's limit, less the IP set suffix."
  }
}
variable "resource_arn" {
  type        = string
  description = "ARN of the load balancer the web ACL is associated with"

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:elasticloadbalancing:[^:]+:[0-9]{12}:loadbalancer/app/", var.resource_arn))
    error_message = "resource_arn must be the ARN of an Application Load Balancer."
  }
}
variable "allowed_ipv4_address_ranges" {
  type        = list(string)
  default     = []
  description = "IPv4 CIDR blocks admitted. Any entry here or in the IPv6 list turns the default action to block"

  validation {
    condition     = alltrue([for range in var.allowed_ipv4_address_ranges : can(regex("^[0-9]{1,3}(\\.[0-9]{1,3}){3}/[0-9]{1,2}$", range)) && can(cidrhost(range, 0))])
    error_message = "allowed_ipv4_address_ranges must contain IPv4 CIDR blocks such as 203.0.113.4/32."
  }
}
variable "allowed_ipv6_address_ranges" {
  type        = list(string)
  default     = []
  description = "IPv6 CIDR blocks admitted"

  validation {
    condition     = alltrue([for range in var.allowed_ipv6_address_ranges : can(regex("^[0-9a-fA-F:]+/[0-9]{1,3}$", range)) && can(cidrhost(range, 0))])
    error_message = "allowed_ipv6_address_ranges must contain IPv6 CIDR blocks such as 2001:db8::/32."
  }
}
variable "rate_limit_enabled" {
  type        = bool
  default     = false
  description = "Whether to block an address that sends more than rate_limit_requests to rate_limited_path within rate_limit_interval_seconds, as the blueprint's waf_rate_limit_enabled"
}
variable "rate_limit_requests" {
  type        = number
  default     = 300
  description = "Requests an address may send to rate_limited_path per interval before it is blocked, 300 as the blueprint's default"

  validation {
    condition     = var.rate_limit_requests >= 10 && var.rate_limit_requests <= 2000000000
    error_message = "rate_limit_requests must be between 10 and 2,000,000,000 - the range a WAF rate-based rule accepts."
  }
}
variable "rate_limit_interval_seconds" {
  type        = number
  default     = 300
  description = "Window the requests are counted over, 300 seconds as the blueprint's default"

  validation {
    condition     = contains([60, 120, 300, 600], var.rate_limit_interval_seconds)
    error_message = "rate_limit_interval_seconds must be 60, 120, 300 or 600 - the evaluation windows WAF offers. The blueprint took any integer and left the rejection to CloudFormation."
  }
}
variable "rate_limited_path" {
  type        = string
  default     = "/api/prompt"
  description = "Path prefix the rate limit counts, ComfyUI's workflow submission API as the blueprint chose it"

  validation {
    condition     = startswith(var.rate_limited_path, "/")
    error_message = "rate_limited_path must start with a slash."
  }
}
