variable "name" {
  type        = string
  default     = "ack-demo-bucket"
  description = "Name of the Kubernetes Bucket object. Distinct from the name of the S3 bucket it creates"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.name))
    error_message = "name must be a valid lowercase RFC 1123 label."
  }
}

variable "namespace" {
  type        = string
  default     = "default"
  description = "Namespace the Bucket object is created in. The ACK capability's baseline access entry policy is cluster-scoped, so any namespace works"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a valid lowercase RFC 1123 label."
  }
}

variable "bucket_name" {
  type        = string
  description = "Name of the S3 bucket ACK creates. Globally unique across all of AWS, so the caller builds it from the account id and region rather than hardcoding one"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.bucket_name))
    error_message = "bucket_name must be 3-63 characters of lowercase letters, digits, dots and hyphens, starting and ending with a letter or digit - the S3 bucket naming rules."
  }
}

variable "capability_dependency" {
  type        = any
  default     = null
  description = "Value the caller passes purely to order this module after the ACK capability. The Bucket CRD does not exist until the capability has installed the controllers (rules.md D-4)"
}
