variable "bucket_name" {
  type        = string
  description = "Name of the bucket. A fixed name rather than a prefix, because the ComfyUI image computes the models and outputs bucket names itself as comfyui-<kind>-<account>-<region> - the caller derives the same string so the two cannot disagree"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.bucket_name)) && !strcontains(var.bucket_name, "..")
    error_message = "bucket_name must be 3-63 characters of lowercase letters, digits, dots and hyphens, starting and ending with a letter or digit."
  }
}
variable "force_destroy" {
  type        = bool
  default     = true
  description = "Whether terraform destroy empties the bucket before deleting it. Every object in these buckets was written by something Terraform does not track - a build, the ComfyUI pod, S3 access logging - so without it destroy stops on BucketNotEmpty. True deletes the data along with the bucket, which the root's teardown output says out loud (rules.md I-4)"
}
variable "expiration_days" {
  type        = number
  default     = null
  description = "Days after which objects are expired by a lifecycle rule, or null for no rule. The models access log bucket uses 90, as the blueprint's lifecycleRules did (rules.md B-4)"

  validation {
    condition     = var.expiration_days == null || try(var.expiration_days >= 1, false)
    error_message = "expiration_days must be at least 1, or null."
  }
}
variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags on the bucket, merged with a Name tag"

  validation {
    condition     = alltrue([for key in keys(var.tags) : length(key) > 0 && !startswith(lower(key), "aws:")])
    error_message = "tags keys must be non-empty and must not use the reserved \"aws:\" prefix."
  }
}
