variable "name" {
  type        = string
  description = "Name of the VPC origin, and the prefix of the distribution's comment"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]{1,64}$", var.name))
    error_message = "name must be 1-64 characters of letters, digits, hyphens and underscores."
  }
}
variable "origin_arn" {
  type        = string
  description = "ARN of the internal load balancer CloudFront reaches through the VPC origin. It has to be Active before the origin can be created, which a Terraform-created aws_lb is by the time its ARN exists"

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:elasticloadbalancing:", var.origin_arn))
    error_message = "origin_arn must be an Elastic Load Balancing ARN."
  }
}
variable "origin_domain_name" {
  type        = string
  description = "DNS name of that load balancer, which a VPC origin still needs as the origin's domain name"

  validation {
    condition     = length(var.origin_domain_name) > 0
    error_message = "origin_domain_name must not be empty."
  }
}
variable "http_port" {
  type        = number
  default     = 80
  description = "Port CloudFront connects to on the load balancer. Has to be a listener the load balancer has - the caller passes the same number the Ingress's listen-ports annotation creates (rules.md B-5)"

  validation {
    condition     = var.http_port > 0 && var.http_port <= 65535
    error_message = "http_port must be a valid TCP port."
  }
}
variable "origin_protocol_policy" {
  type        = string
  default     = "http-only"
  description = "Protocol CloudFront uses to the origin. http-only, as the blueprint had it: a VPC origin travels over AWS's private network rather than the internet, and HTTPS to an internal ALB would need a certificate from a private CA"

  validation {
    condition     = contains(["http-only", "https-only", "match-viewer"], var.origin_protocol_policy)
    error_message = "origin_protocol_policy must be http-only, https-only or match-viewer."
  }
}
variable "cache_policy_id" {
  type        = string
  description = "Cache policy for the default behavior. The caller passes Managed-CachingDisabled, as the blueprint did: everything ComfyUI serves is either dynamic or a WebSocket"

  validation {
    condition     = length(var.cache_policy_id) > 0
    error_message = "cache_policy_id must not be empty."
  }
}
variable "origin_request_policy_id" {
  type        = string
  description = "Origin request policy for the default behavior. The caller passes Managed-AllViewer, as the blueprint did: the WebSocket upgrade and ComfyUI's own headers have to reach the origin"

  validation {
    condition     = length(var.origin_request_policy_id) > 0
    error_message = "origin_request_policy_id must not be empty."
  }
}
variable "origin_read_timeout" {
  type        = number
  default     = 30
  description = "How long CloudFront waits for the origin to start responding, in seconds. 30, CloudFront's default and what the blueprint's distribution had; a VPC origin allows up to 60 without a quota increase"

  validation {
    condition     = var.origin_read_timeout >= 1 && var.origin_read_timeout <= 60
    error_message = "origin_read_timeout must be between 1 and 60 seconds."
  }
}
variable "price_class" {
  type        = string
  default     = "PriceClass_All"
  description = "CloudFront price class. PriceClass_All, which is what the blueprint's distribution got by not setting one"

  validation {
    condition     = contains(["PriceClass_All", "PriceClass_200", "PriceClass_100"], var.price_class)
    error_message = "price_class must be one of: PriceClass_All, PriceClass_200, PriceClass_100."
  }
}
