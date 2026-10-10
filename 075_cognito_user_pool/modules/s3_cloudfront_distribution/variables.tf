variable "bucket_prefix" {
  type        = string
  description = "Prefix for the generated origin bucket name. The _monolithic template let Terraform generate the whole name"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{0,36}$", var.bucket_prefix))
    error_message = "bucket_prefix must be 1-37 characters of lowercase letters, digits, periods and hyphens, starting with a letter or digit."
  }
}
variable "origin_access_control_name" {
  type        = string
  description = "Name of the origin access control. Unique per account"

  validation {
    condition     = length(var.origin_access_control_name) > 0 && length(var.origin_access_control_name) <= 64
    error_message = "origin_access_control_name must be 1-64 characters."
  }
}
variable "comment" {
  type        = string
  default     = null
  description = "Comment shown with the distribution in the console"
}
variable "default_root_object" {
  type        = string
  default     = null
  description = "Object served for a request to /, and the page the single-page app fallback answers with. Null serves nothing at /, as the _monolithic template's image distribution had it"

  validation {
    condition     = var.default_root_object == null || (length(coalesce(var.default_root_object, "x")) > 0 && !startswith(coalesce(var.default_root_object, "x"), "/"))
    error_message = "default_root_object must not be empty and must not start with a slash, or be null."
  }
}
variable "spa_fallback" {
  type        = bool
  default     = false
  description = "Whether 403 and 404 from the bucket are answered with the default root object and a 200, as a single-page app needs"

  validation {
    # The fallback answers with the root object, so there has to be one (rules.md B-1).
    condition     = !var.spa_fallback || var.default_root_object != null
    error_message = "spa_fallback needs default_root_object set - the fallback answers with that page."
  }
}
variable "price_class" {
  type        = string
  default     = "PriceClass_All"
  description = "Edge locations the distribution uses"

  validation {
    condition     = contains(["PriceClass_All", "PriceClass_200", "PriceClass_100"], var.price_class)
    error_message = "price_class must be PriceClass_All, PriceClass_200 or PriceClass_100."
  }
}
variable "default_allowed_methods" {
  type        = list(string)
  default     = ["GET", "HEAD"]
  description = "Methods the bucket behaviour accepts, and caches"

  validation {
    # Compared as joined strings: contains() over list literals of different lengths compares a list(string)
    # against tuples, which never match, so every value - the default included - would be rejected.
    condition     = contains(["GET,HEAD", "GET,HEAD,OPTIONS"], join(",", var.default_allowed_methods))
    error_message = "default_allowed_methods must be [\"GET\", \"HEAD\"] or [\"GET\", \"HEAD\", \"OPTIONS\"] - the sets CloudFront allows a cacheable behaviour."
  }
}
variable "websocket_origin" {
  type = object({
    domain_name       = string
    http_port         = optional(number, 80)
    path_pattern      = string
    forwarded_headers = list(string)
  })
  default     = null
  description = "A second origin, an HTTP load balancer, for the paths matching path_pattern, with the websocket headers forwarded. Null serves the bucket only"
}
