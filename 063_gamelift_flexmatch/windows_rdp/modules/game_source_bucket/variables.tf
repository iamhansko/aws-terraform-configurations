variable "bucket_prefix" {
  type        = string
  default     = "gamelift-flexmatch-game-source-"
  description = "Prefix for the generated bucket name. A prefix because S3 names are global and the _monolithic template left the name to the provider; the generated suffix keeps a second copy of this project from colliding"

  validation {
    # bucket_prefix leaves 26 characters of the 63 for the provider's suffix.
    condition     = length(var.bucket_prefix) <= 37 && can(regex("^[a-z0-9][a-z0-9.-]*$", var.bucket_prefix))
    error_message = "bucket_prefix must be at most 37 characters of lowercase letters, digits, dots and hyphens, starting with a letter or digit."
  }
}
variable "force_destroy" {
  type        = bool
  default     = true
  description = "Whether destroy deletes the bucket with its objects in it. True: every object here - server.zip, client.zip, Lambda/code.zip and the rest of the uploaded clone - was put there by the instance, not by Terraform, so destroy fails with BucketNotEmpty without this. The uploads go with the bucket, and nothing else holds a copy of the server build with this deployment's config.ini baked in"
}
