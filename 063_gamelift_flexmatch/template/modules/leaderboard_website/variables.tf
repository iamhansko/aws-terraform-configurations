variable "bucket_prefix" {
  type        = string
  description = "Prefix for the generated bucket name. The _monolithic template let CloudFormation generate the name"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]*$", var.bucket_prefix)) && length(var.bucket_prefix) <= 37
    error_message = "bucket_prefix must be 1-37 characters of lowercase letters, digits, dots and hyphens, starting with a letter or digit."
  }
}
variable "force_destroy" {
  type        = bool
  default     = true
  description = "Whether terraform destroy empties the bucket first. True because the site files are uploaded by the workbench rather than by Terraform, so without it destroy stops at BucketNotEmpty. The uploaded site is deleted with the bucket"
}
variable "index_document" {
  type        = string
  default     = "index.html"
  description = "Index document of the static website, as the _monolithic template had it"

  validation {
    condition     = length(var.index_document) > 0 && !strcontains(var.index_document, "/")
    error_message = "index_document must be a non-empty object name without a slash."
  }
}
