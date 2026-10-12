variable "name" {
  type        = string
  description = "Name of the user pool, and the prefix of the pre sign-up function and the roles"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,40}$", var.name))
    error_message = "name must be 2-41 characters of lowercase letters, digits and hyphens."
  }
}
variable "region" {
  type        = string
  description = "Region the pool is in, for the hosted UI's address"

  validation {
    condition     = can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]$", var.region))
    error_message = "region must be an AWS region name such as ap-northeast-2."
  }
}
variable "partition" {
  type        = string
  default     = "aws"
  description = "AWS partition, for the managed policy ARN"

  validation {
    condition     = contains(["aws", "aws-cn", "aws-us-gov"], var.partition)
    error_message = "partition must be aws, aws-cn or aws-us-gov."
  }
}
variable "domain_prefix" {
  type        = string
  description = "Prefix of the hosted UI domain, <prefix>.auth.<region>.amazoncognito.com. Unique per region across every account, which is why the caller derives it from a hash"

  validation {
    # Cognito's own rule, plus its refusal of prefixes containing aws, amazon or cognito.
    condition     = can(regex("^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$", var.domain_prefix)) && length(regexall("aws|amazon|cognito", var.domain_prefix)) == 0
    error_message = "domain_prefix must be 1-63 lowercase letters, digits and hyphens, not beginning or ending with a hyphen, and must not contain aws, amazon or cognito."
  }
}
variable "application_dns_name" {
  type        = string
  description = "DNS name the application is reached at - the load balancer's. The callback and sign-out URLs are built from it, lowercased"

  validation {
    condition     = length(var.application_dns_name) > 0 && !can(regex("^https?://", var.application_dns_name))
    error_message = "application_dns_name must be a bare DNS name, without a scheme."
  }
}
variable "client_name" {
  type        = string
  default     = "alb-app-client"
  description = "Name of the app client the load balancer uses - the blueprint's construct ID for it"

  validation {
    condition     = can(regex("^[\\w\\s+=,.@-]{1,128}$", var.client_name))
    error_message = "client_name must be 1-128 characters of letters, digits, spaces and + = , . @ - _."
  }
}
variable "self_sign_up_enabled" {
  type        = bool
  default     = false
  description = "Whether anyone can create an account on the hosted UI. With false, only an administrator can add users"
}
variable "allowed_sign_up_email_domains" {
  type        = list(string)
  default     = []
  description = "Email domains allowed to register. Empty means no check at all, the blueprint's None; a non-empty list adds the pre sign-up function that rejects every other domain"

  validation {
    condition     = alltrue([for domain in var.allowed_sign_up_email_domains : can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$", domain))])
    error_message = "allowed_sign_up_email_domains must contain bare domains such as example.co.jp, without an @."
  }
}
variable "mfa_required" {
  type        = bool
  default     = false
  description = "Whether every user must set up a second factor, the blueprint's mfa_required. With false, MFA is optional and offered as SMS or an authenticator app"
}
variable "advanced_security_mode" {
  type        = string
  default     = "ENFORCED"
  description = "Cognito threat protection mode, ENFORCED as the blueprint had it. Any mode but OFF puts the pool on the Plus feature plan, which is billed for every monthly active user with no free tier; OFF puts it on Essentials"

  validation {
    condition     = contains(["ENFORCED", "AUDIT", "OFF"], var.advanced_security_mode)
    error_message = "advanced_security_mode must be ENFORCED, AUDIT or OFF."
  }
}
variable "sms_external_id" {
  type        = string
  description = "External ID Cognito presents when it assumes the SMS role. Not a secret; it ties the role to this pool"

  validation {
    # The length is checked apart from the pattern because RE2, Terraform's regex engine, refuses a repetition
    # count above 1000 - inside can() that is a pattern that never matches rather than an error.
    condition     = can(regex("^[\\w+=,.@:/-]+$", var.sms_external_id)) && length(var.sms_external_id) >= 2 && length(var.sms_external_id) <= 1224
    error_message = "sms_external_id must be 2-1224 characters of letters, digits and + = , . @ : / - _."
  }
}
variable "lambda_runtime" {
  type        = string
  default     = "python3.12"
  description = "Runtime of the pre sign-up function, python3.12 as the blueprint had it"

  validation {
    condition     = can(regex("^python3\\.(1[2-9]|[2-9][0-9])$", var.lambda_runtime))
    error_message = "lambda_runtime must be python3.12 or newer."
  }
}
variable "pre_sign_up_source_zip_path" {
  type        = string
  description = "Path of the zipped pre sign-up function. Zipped by the caller, so the archive is read at plan even though this module is ordered after the network (rules.md D-6)"

  validation {
    condition     = endswith(var.pre_sign_up_source_zip_path, ".zip")
    error_message = "pre_sign_up_source_zip_path must point at a .zip file."
  }
}
variable "pre_sign_up_source_code_hash" {
  type        = string
  description = "Base64 SHA-256 of that zip, which is what redeploys the function when its code changes"

  validation {
    condition     = length(var.pre_sign_up_source_code_hash) > 0
    error_message = "pre_sign_up_source_code_hash must not be empty."
  }
}
variable "log_retention_days" {
  type        = number
  default     = 731
  description = "Retention of the pre sign-up function's log group. The blueprint declared none, so Lambda created one that never expired and outlived the stack"

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be one of the retention periods CloudWatch Logs accepts."
  }
}
