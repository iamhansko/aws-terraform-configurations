variable "bucket_name" {
  type        = string
  default     = null
  description = "Fixed bucket name. Null generates one from bucket_name_prefix, which is what lets this project be deployed twice in one account - bucket names are globally unique, so a fixed one is a collision waiting for the second deployment. The _monolithic template declared a bare aws_s3_bucket with no arguments at all, which also generates a name but leaves everything else at the provider's defaults"

  validation {
    condition     = var.bucket_name == null || can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.bucket_name))
    error_message = "bucket_name must be 3-63 characters of lowercase letters, digits, dots and hyphens, or null to generate one."
  }
}
variable "bucket_name_prefix" {
  type        = string
  default     = "eks-pod-credentials-"
  description = "Prefix for the generated bucket name when bucket_name is null"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,36}$", var.bucket_name_prefix))
    error_message = "bucket_name_prefix must be lowercase letters, digits, dots and hyphens, and short enough to leave room for the generated suffix."
  }
}
variable "force_destroy" {
  type        = bool
  default     = true
  description = "Whether terraform destroy empties the bucket before deleting it. True, because this bucket exists for a demo that writes into it from a pod: with it false, an object put there by hand blocks the destroy with BucketNotEmpty and the rest of the stack goes with it. Never true for a bucket holding anything worth keeping"
}
variable "object_keys" {
  type        = list(string)
  default     = ["hello-from-terraform.txt"]
  description = "Objects written into the bucket so that \"aws s3 ls\" from inside a pod prints something. Without them the command succeeds with no output, which looks exactly like the permission having been denied and silently swallowed - and that ambiguity is the last thing this project needs, since telling success from failure is the whole exercise"

  validation {
    condition     = alltrue([for key in var.object_keys : length(key) > 0])
    error_message = "object_keys must not contain empty keys."
  }
}
