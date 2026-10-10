variable "name" {
  type        = string
  default     = "service-connect-test"
  description = "Name of the namespace, as the _monolithic template had it. Cloud Map rejects a second namespace of the same name in one account and region with NamespaceAlreadyExists, so a second copy of this project needs a different value. Changing it replaces the namespace, which Cloud Map refuses while the ECS services still have endpoints in it"

  validation {
    # Length checked apart from the pattern: RE2 caps a repetition count at 1000, so {1,1024} fails to compile
    # and can() would reject every name.
    condition     = length(var.name) <= 1024 && can(regex("^[!-~]+$", var.name))
    error_message = "name must be 1-1024 printable ASCII characters with no spaces, which is what Cloud Map accepts for an HTTP namespace name."
  }
}
variable "description" {
  type        = string
  default     = "Namespace for ECS Service Connect"
  description = "Description of the namespace, as the _monolithic template had it"

  validation {
    condition     = length(var.description) <= 1024
    error_message = "description must be 1024 characters or fewer."
  }
}
