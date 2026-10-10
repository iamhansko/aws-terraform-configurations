variable "repositories" {
  type        = map(string)
  description = "Repositories to create, keyed by a caller-chosen label, value the repository name"

  validation {
    condition     = length(var.repositories) > 0 && alltrue([for name in values(var.repositories) : can(regex("^[a-z0-9]+(?:[._-][a-z0-9]+)*(?:/[a-z0-9]+(?:[._-][a-z0-9]+)*)*$", name)) && length(name) <= 256])
    error_message = "repositories must name at least one repository, each in ECR's form: lowercase letters, digits and ._-/ separators, 256 characters or fewer."
  }
}
variable "scan_on_push" {
  type        = bool
  default     = false
  description = "Whether ECR scans each image when it is pushed. Off, as the _monolithic template left it"
}
