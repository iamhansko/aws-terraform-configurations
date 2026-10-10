variable "name" {
  type        = string
  default     = "BuilderClass01"
  description = "Name of the identity pool, as the _monolithic template had it, and the prefix of its two roles"

  validation {
    condition     = can(regex("^[\\w\\s+=,.@-]{1,128}$", var.name))
    error_message = "name must be 1-128 characters of letters, digits, spaces and _+=,.@-."
  }
}
variable "user_pool_client_id" {
  type        = string
  description = "App client whose tokens the identity pool accepts"

  validation {
    condition     = length(var.user_pool_client_id) > 0
    error_message = "user_pool_client_id must not be empty."
  }
}
variable "user_pool_endpoint" {
  type        = string
  description = "The user pool's issuer, cognito-idp.<region>.amazonaws.com/<pool id>. This exact string is also the key a browser puts its ID token under in logins, so the two have to match character for character"

  validation {
    condition     = can(regex("^cognito-idp\\.[a-z0-9-]+\\.amazonaws\\.com/[a-z0-9-]+_[A-Za-z0-9]+$", var.user_pool_endpoint))
    error_message = "user_pool_endpoint must be cognito-idp.<region>.amazonaws.com/<user pool id>, without a scheme."
  }
}
variable "allow_unauthenticated_identities" {
  type        = bool
  default     = true
  description = "Whether a visitor who has not signed in still gets an identity and guest credentials, as the _monolithic template had it"
}
variable "listable_bucket_arns" {
  type        = list(string)
  description = "Buckets a signed-in identity may list"

  validation {
    condition     = length(var.listable_bucket_arns) > 0 && alltrue([for arn in var.listable_bucket_arns : can(regex("^arn:aws[a-zA-Z-]*:s3:::[a-z0-9.-]+$", arn))])
    error_message = "listable_bucket_arns must contain at least one S3 bucket ARN (arn:aws:s3:::<bucket>)."
  }
}
