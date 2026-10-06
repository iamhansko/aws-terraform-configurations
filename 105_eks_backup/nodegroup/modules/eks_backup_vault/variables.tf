variable "name" {
  type        = string
  description = "Name of the vault, and the prefix the role, topic, queue and plan names are generated from. Taken from the caller rather than defaulted, because the _monolithic template hardcoded the vault as \"eks\" and a vault cannot be renamed - so a second copy of the project in one account collides permanently"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-_]{0,48}$", var.name))
    error_message = "name must be 1-49 characters of letters, digits, hyphens and underscores, starting with a letter or digit - the character set a backup vault name accepts."
  }
}

variable "force_destroy" {
  type        = bool
  default     = true
  description = "Whether `terraform destroy` deletes the vault's recovery points first. True for a demo: AWS Backup refuses to delete a vault that still holds any, and a backup demo always holds some"
}

variable "kms_key_arn" {
  type        = string
  default     = null
  description = "Customer managed KMS key for the vault, or null to use the AWS Backup default key. A cross-account or cross-region copy needs a customer managed key; a single-account demo does not"

  validation {
    condition     = var.kms_key_arn == null || can(regex("^arn:aws:kms:", var.kms_key_arn))
    error_message = "kms_key_arn must be a KMS key ARN, or null."
  }
}

variable "iam_policy_arns" {
  type = list(string)
  default = [
    "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup",
    "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores",
    "arn:aws:iam::aws:policy/AWSBackupServiceRolePolicyForS3Backup",
    "arn:aws:iam::aws:policy/AWSBackupServiceRolePolicyForS3Restore",
  ]
  description = <<-DESC
    Managed policies attached to the role AWS Backup assumes, as the _monolithic template attached.

    All four, and the two S3 ones are the pair that is easy to think unnecessary. An EKS backup is a
    composite recovery point with a child for every volume the cluster's claims reference, so a cluster
    with a bucket-backed claim needs the S3 permissions too - without them the parent recovery point is
    still reported as completed and the child for the bucket is simply absent.

    Note the path difference: the EKS-side policies live under service-role/ and the S3 ones do not.
  DESC

  validation {
    condition     = alltrue([for arn in var.iam_policy_arns : can(regex("^arn:aws:iam::", arn))])
    error_message = "iam_policy_arns must contain valid IAM policy ARNs."
  }
}

variable "backup_vault_events" {
  type        = list(string)
  default     = ["EKS_RESTORE_OBJECT_FAILED", "EKS_RESTORE_OBJECT_SKIPPED"]
  description = <<-DESC
    Vault events published to the topic, as the _monolithic template subscribed them.

    These two are the interesting pair for EKS. A restore job reports COMPLETED even when it skipped
    objects it could not recreate - Services and Ingresses always, and anything whose CRD is missing on
    the target cluster - and the list of what was skipped exists only as these events.
  DESC

  validation {
    condition     = length(var.backup_vault_events) > 0
    error_message = "backup_vault_events must name at least one event; an empty list creates a notification that delivers nothing."
  }
}

variable "message_retention_seconds" {
  type        = number
  default     = 3600
  description = "How long the queue keeps an event, as the _monolithic template set it. One hour is enough to read a restore's skip list while the restore is still fresh"

  validation {
    condition     = var.message_retention_seconds >= 60 && var.message_retention_seconds <= 1209600
    error_message = "message_retention_seconds must be between 60 and 1209600 (14 days)."
  }
}

variable "visibility_timeout_seconds" {
  type        = number
  default     = 30
  description = "Queue visibility timeout. Left at the SQS default because nothing consumes this queue automatically - it is read by hand"

  validation {
    condition     = var.visibility_timeout_seconds >= 0 && var.visibility_timeout_seconds <= 43200
    error_message = "visibility_timeout_seconds must be between 0 and 43200."
  }
}

variable "create_backup_plan" {
  type        = bool
  default     = true
  description = <<-DESC
    Whether to create a backup plan and a selection covering protected_resource_arns.

    True, and this is the part the _monolithic template did not have. It started a single job with
    `aws backup start-backup-job` from a shell inside an SSM Association, which means the cluster had
    exactly one recovery point - taken at the moment of the apply, before any of the workloads it was
    meant to demonstrate existed. A plan makes the backup a property of the configuration rather than of
    something somebody ran.
  DESC
}

variable "protected_resource_arns" {
  type        = list(string)
  default     = []
  description = "ARNs the plan's selection covers, normally the EKS cluster's. Handed in rather than discovered, so this module knows nothing about the cluster (rules.md B-6)"

  validation {
    condition     = alltrue([for arn in var.protected_resource_arns : can(regex("^arn:aws:", arn))])
    error_message = "protected_resource_arns must contain valid ARNs."
  }

  validation {
    # The pair, not either value alone: a plan with an empty selection is accepted and protects nothing,
    # which is indistinguishable from a working plan until the first scheduled run does not appear
    # (rules.md B-1).
    condition     = var.create_backup_plan == false || length(var.protected_resource_arns) > 0
    error_message = "protected_resource_arns must name at least one resource when create_backup_plan is true; a selection with no resources produces a plan that runs and backs up nothing."
  }
}

variable "backup_schedule" {
  type        = string
  default     = "cron(0 3 * * ? *)"
  description = "Cron expression for the plan's rule, in UTC. Daily at 03:00 by default"

  validation {
    condition     = can(regex("^(cron|rate)\\(", var.backup_schedule))
    error_message = "backup_schedule must be a cron() or rate() expression."
  }
}

variable "start_window_minutes" {
  type        = number
  default     = 60
  description = "How long AWS Backup waits for the job to start before abandoning it"

  validation {
    condition     = var.start_window_minutes >= 60
    error_message = "start_window_minutes must be at least 60, which is the minimum AWS Backup accepts."
  }
}

variable "completion_window_minutes" {
  type        = number
  default     = 480
  description = "How long the job may run. Raised well above the default because an EKS backup walks every object in the cluster and then snapshots every attached volume - exceeding it produces an ABORTED job rather than a partial one"

  validation {
    condition     = var.completion_window_minutes > var.start_window_minutes
    error_message = "completion_window_minutes must be greater than start_window_minutes, since the completion window is measured from the scheduled time."
  }
}

variable "delete_after_days" {
  type        = number
  default     = 7
  description = "How long a recovery point is kept. Short by default, because these are demo clusters and a retained composite recovery point keeps every child snapshot alive with it"

  validation {
    condition     = var.delete_after_days >= 1
    error_message = "delete_after_days must be at least 1."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags applied to the vault, role, topic, queue and plan"
}
