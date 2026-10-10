variable "name" {
  type        = string
  description = "Name of the function. Unique per account rather than per region, so the caller makes it unique"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]{1,64}$", var.name))
    error_message = "name must be 1-64 characters of letters, digits, hyphens and underscores."
  }
}
variable "comment" {
  type        = string
  default     = null
  description = "Comment shown with the function in the console"

  validation {
    condition     = var.comment == null || length(coalesce(var.comment, "x")) <= 128
    error_message = "comment must be 128 characters or fewer."
  }
}
variable "runtime" {
  type        = string
  default     = "cloudfront-js-2.0"
  description = "Function runtime, as the _monolithic template had it. 2.0 is required for a key value store"

  validation {
    condition     = contains(["cloudfront-js-1.0", "cloudfront-js-2.0"], var.runtime)
    error_message = "runtime must be cloudfront-js-1.0 or cloudfront-js-2.0."
  }
  validation {
    # The 1.0 runtime cannot read a key value store, and CloudFront accepts the association anyway - the
    # failure is the function throwing at the edge on its first request (rules.md B-1).
    condition     = var.key_value_store_name == null || var.runtime == "cloudfront-js-2.0"
    error_message = "runtime must be cloudfront-js-2.0 when key_value_store_name is set - only the 2.0 runtime can read a key value store."
  }
}
variable "code" {
  type        = string
  description = "Function source. Read from a file by the caller"

  validation {
    # CloudFront's own limit for function code.
    condition     = length(var.code) > 0 && length(var.code) <= 10240
    error_message = "code must be between 1 and 10240 bytes."
  }
  validation {
    condition     = can(regex("function\\s+handler\\s*\\(", var.code))
    error_message = "code must define function handler(event) - CloudFront calls nothing else."
  }
}
variable "key_value_store_name" {
  type        = string
  default     = null
  description = "Name of a key value store to create and associate with the function. Null creates none. Unique per account, like the function name"

  validation {
    condition     = var.key_value_store_name == null || can(regex("^[a-zA-Z0-9-_]{1,64}$", coalesce(var.key_value_store_name, "x")))
    error_message = "key_value_store_name must be 1-64 characters of letters, digits, hyphens and underscores, or null."
  }
}
