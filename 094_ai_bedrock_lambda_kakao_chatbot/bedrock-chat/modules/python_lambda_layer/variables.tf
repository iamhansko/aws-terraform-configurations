variable "layer_name" {
  type        = string
  description = "Name of the layer, and the stem of the builder function, its role and the package bucket"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-_]{0,63}$", var.layer_name))
    error_message = "layer_name must start with a letter and be up to 64 characters of letters, digits, hyphens and underscores."
  }
}
variable "description" {
  type        = string
  default     = ""
  description = "Description of the layer version"

  validation {
    condition     = length(var.description) <= 256
    error_message = "description must be 256 characters or fewer."
  }
}
variable "requirements" {
  type        = list(string)
  description = "pip requirements the layer contains, each pinned to an exact version (name==version), so a rebuild produces the same packages and a version bump is a change in the plan"

  validation {
    condition     = length(var.requirements) > 0
    error_message = "requirements must name at least one package."
  }
  validation {
    # Exact pins only. A bare name or a range would make the layer's contents depend on the day of the build,
    # while nothing in the plan changes.
    condition     = alltrue([for requirement in var.requirements : can(regex("^[A-Za-z0-9][A-Za-z0-9._-]*(\\[[A-Za-z0-9._,-]+\\])?==[0-9][A-Za-z0-9.+!-]*$", requirement))])
    error_message = "each requirement must be pinned as name==version (extras allowed, e.g. name[extra]==1.2.3)."
  }
}
variable "runtime" {
  type        = string
  description = "Python runtime the layer is built on and published for. The functions using it must run the same one"

  validation {
    condition     = can(regex("^python3\\.[0-9]+$", var.runtime))
    error_message = "runtime must be a Python runtime, e.g. python3.12."
  }
}
variable "architecture" {
  type        = string
  default     = "x86_64"
  description = "Instruction set architecture the layer is built on and published for"

  validation {
    condition     = contains(["x86_64", "arm64"], var.architecture)
    error_message = "architecture must be x86_64 or arm64."
  }
}
variable "builder_memory_size" {
  type        = number
  default     = 2048
  description = "Memory in MB for the builder function. pip is mostly network-bound, but memory also buys CPU, which the zip step uses"

  validation {
    condition     = var.builder_memory_size >= 512 && var.builder_memory_size <= 10240 && floor(var.builder_memory_size) == var.builder_memory_size
    error_message = "builder_memory_size must be an integer between 512 and 10240."
  }
}
variable "builder_timeout" {
  type        = number
  default     = 900
  description = "Seconds the build may take - the Lambda maximum, because a cold PyPI download of a large tree is the slow case"

  validation {
    condition     = var.builder_timeout >= 60 && var.builder_timeout <= 900 && floor(var.builder_timeout) == var.builder_timeout
    error_message = "builder_timeout must be an integer between 60 and 900."
  }
}
variable "builder_ephemeral_storage_size" {
  type        = number
  default     = 4096
  description = "Size of /tmp for the builder in MB. It holds the installed tree and its zip at once"

  validation {
    condition     = var.builder_ephemeral_storage_size >= 512 && var.builder_ephemeral_storage_size <= 10240 && floor(var.builder_ephemeral_storage_size) == var.builder_ephemeral_storage_size
    error_message = "builder_ephemeral_storage_size must be an integer between 512 and 10240."
  }
}
variable "log_retention_in_days" {
  type        = number
  default     = 7
  description = "Days the builder's log group keeps events"

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_in_days)
    error_message = "log_retention_in_days must be one of the values CloudWatch Logs accepts: 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288 or 3653."
  }
}
