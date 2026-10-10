variable "bucket_prefix" {
  type        = string
  default     = "gamelift-flexmatch-web-"
  description = "Prefix for the generated bucket name. A prefix because S3 names are global and the _monolithic template left the name to the provider"

  validation {
    # bucket_prefix leaves 26 characters of the 63 for the provider's suffix.
    condition     = length(var.bucket_prefix) <= 37 && can(regex("^[a-z0-9][a-z0-9.-]*$", var.bucket_prefix))
    error_message = "bucket_prefix must be at most 37 characters of lowercase letters, digits, dots and hyphens, starting with a letter or digit."
  }
}
variable "force_destroy" {
  type        = bool
  default     = true
  description = "Whether destroy deletes the bucket with its objects in it. True: the page files are uploaded by the instance, not by Terraform, so destroy fails with BucketNotEmpty without this. The uploaded page goes with the bucket"
}
variable "index_document" {
  type        = string
  default     = "index.html"
  description = "Object served for a request to the website root, as the _monolithic template had it"

  validation {
    condition     = length(var.index_document) > 0 && !strcontains(var.index_document, "/")
    error_message = "index_document must be a non-empty object name without a slash - S3 rejects a website index document suffix containing one."
  }
}
