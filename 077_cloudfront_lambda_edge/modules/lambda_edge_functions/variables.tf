variable "name_prefix" {
  type        = string
  description = "Prefix for the function names (<prefix>-<key>) and the role name. The _monolithic template derived both function names from its stack name the same way"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]{1,23}$", var.name_prefix))
    error_message = "name_prefix must be 1-23 characters of letters, digits, hyphens and underscores, leaving room for the function key inside Lambda's 64-character limit."
  }
}
variable "functions" {
  type = map(object({
    source_file = string
    description = optional(string)
  }))
  description = "Functions to create, keyed by a caller-chosen label that becomes the end of the function name. A map of literal keys, so the resource addresses are known at plan (rules.md B-8)"

  validation {
    condition     = length(var.functions) > 0 && alltrue([for key in keys(var.functions) : can(regex("^[a-z0-9-]{1,40}$", key))])
    error_message = "functions must be non-empty, and each key must be 1-40 lowercase letters, digits or hyphens."
  }
  validation {
    condition     = alltrue([for f in values(var.functions) : endswith(f.source_file, ".js") || endswith(f.source_file, ".mjs")])
    error_message = "each function's source_file must be a .js or .mjs file - the handler is index.handler on a Node.js runtime."
  }
}
variable "runtime" {
  type        = string
  default     = "nodejs22.x"
  description = "Lambda runtime, as the _monolithic template had it. Lambda@Edge supports Node.js and Python only"

  validation {
    condition     = can(regex("^nodejs[0-9]+\\.x$", var.runtime))
    error_message = "runtime must be a Node.js runtime (e.g. nodejs22.x) - the handlers are JavaScript."
  }
}
variable "delete_timeout" {
  type        = string
  default     = "60m"
  description = "How long terraform destroy keeps retrying the delete of a replicated function. See the timeouts block in main.tf"

  validation {
    condition     = can(regex("^[0-9]+(m|h)$", var.delete_timeout))
    error_message = "delete_timeout must be a duration in minutes or hours, such as 60m or 2h."
  }
}
