variable "bucket_prefix" {
  type        = string
  default     = "cognito-identity-pool-"
  description = "Prefix for the generated bucket name. The _monolithic template let Terraform generate the whole name"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{0,36}$", var.bucket_prefix))
    error_message = "bucket_prefix must be 1-37 characters of lowercase letters, digits, periods and hyphens, starting with a letter or digit."
  }
}
variable "force_destroy" {
  type        = bool
  default     = true
  description = "Whether terraform destroy empties the bucket first, which covers anything uploaded by hand during the workshop"
}
variable "cors_allowed_origins" {
  type        = list(string)
  default     = ["*"]
  description = "Origins allowed to call the bucket from a browser. Any, as the _monolithic template had it - the request is still signed with the identity's credentials, so CORS decides only which pages may try"

  validation {
    condition     = length(var.cors_allowed_origins) > 0
    error_message = "cors_allowed_origins must contain at least one origin."
  }
}
variable "sample_objects" {
  type = map(string)
  default = {
    "Legal/legal.txt"             = "Legal\n"
    "Engineering/engineering.txt" = "Engineering\n"
  }
  description = "Objects to put in the bucket, key to content, as the _monolithic template wrote them. One per department prefix, which is what a principal-tag condition on the list permission would later tell apart"

  validation {
    condition     = alltrue([for key in keys(var.sample_objects) : length(key) > 0 && !startswith(key, "/")])
    error_message = "sample_objects keys must be non-empty object keys that do not start with a slash."
  }
}
