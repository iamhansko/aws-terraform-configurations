variable "account_id" {
  type        = string
  description = "Account this recorder belongs to. Injected rather than read here with data.aws_caller_identity, so the bucket policy's SourceAccount conditions and the delivery prefix are known at plan time instead of after apply (rules.md B-6)"

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be a 12-digit AWS account ID."
  }
}
variable "region" {
  type        = string
  description = "Region this recorder runs in, used only to build the verification commands in the outputs. Injected for the same reason as account_id"

  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]$", var.region))
    error_message = "region must look like an AWS region (e.g. ap-northeast-2)."
  }
}
variable "recorder_name" {
  type        = string
  default     = "default"
  description = "Name of the configuration recorder. One customer managed recorder is allowed per account per region, and PutConfigurationRecorder is an upsert, so this name is also how an apply can silently adopt a recorder something else created"

  validation {
    condition     = can(regex("^[a-zA-Z0-9._-]{1,256}$", var.recorder_name))
    error_message = "recorder_name must be 1-256 characters of letters, digits, dots, underscores and hyphens."
  }
}
variable "delivery_channel_name" {
  type        = string
  default     = "default"
  description = "Name of the delivery channel. Also one per account per region"

  validation {
    condition     = can(regex("^[a-zA-Z0-9._-]{1,256}$", var.delivery_channel_name))
    error_message = "delivery_channel_name must be 1-256 characters of letters, digits, dots, underscores and hyphens."
  }
}
variable "recorder_enabled" {
  type        = bool
  default     = true
  description = "Whether to start the recorder. Creating the recorder resource does not start it - see the aws_config_configuration_recorder_status resource in main.tf for why this is a separate decision in Terraform and was not one in CloudFormation"
}
variable "snapshot_delivery_frequency" {
  type        = string
  default     = "One_Hour"
  description = "How often a full configuration snapshot is written to the bucket. Separate from recording_frequency: that one decides when a change becomes a configuration item, this one decides when the complete inventory is dumped to S3"

  validation {
    condition     = contains(["One_Hour", "Three_Hours", "Six_Hours", "Twelve_Hours", "TwentyFour_Hours"], var.snapshot_delivery_frequency)
    error_message = "snapshot_delivery_frequency must be one of One_Hour, Three_Hours, Six_Hours, Twelve_Hours, TwentyFour_Hours."
  }
}
variable "recording_frequency" {
  type        = string
  default     = "CONTINUOUS"
  description = "CONTINUOUS records every change as it happens, as the _monolithic template had it, which is what a change-triggered rule needs. DAILY records one configuration item per resource per day and costs far less, at the price of the rule evaluating up to a day after the change that should have triggered it"

  validation {
    condition     = contains(["CONTINUOUS", "DAILY"], var.recording_frequency)
    error_message = "recording_frequency must be CONTINUOUS or DAILY."
  }
}
variable "excluded_resource_types" {
  type        = list(string)
  default     = []
  description = "Resource types left out of recording. Everything else in the account is recorded: this module uses the EXCLUSION_BY_RESOURCE_TYPES strategy the _monolithic template chose, so an empty list here means record absolutely everything"

  validation {
    condition     = alltrue([for type in var.excluded_resource_types : can(regex("^AWS::[A-Za-z0-9]+::[A-Za-z0-9]+$", type))])
    error_message = "excluded_resource_types must contain AWS::Service::Resource type names (e.g. AWS::IAM::Role)."
  }
}
variable "bucket_name_prefix" {
  type        = string
  description = "Prefix for the generated delivery bucket name. A prefix rather than a fixed name because S3 bucket names are globally unique; the _monolithic template declared a bare aws_s3_bucket and let the provider generate the whole name, which works and produces a name that says nothing about what the bucket holds"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,40}$", var.bucket_name_prefix))
    error_message = "bucket_name_prefix must be 2-41 characters of lowercase letters, digits, dots and hyphens, leaving room for the generated suffix inside S3's 63 character limit."
  }
}
variable "bucket_force_destroy" {
  type        = bool
  default     = true
  description = "Whether terraform destroy empties the bucket first. Config writes objects Terraform never created, so with this false a destroy stops at BucketNotEmpty after the rest of the project is already gone"
}
variable "role_name_prefix" {
  type        = string
  default     = "config-recorder-"
  description = "Prefix for the generated name of the role AWS Config assumes. The _monolithic template left the name entirely to the provider, which produces terraform-20250101000000000000000001 - unhelpful in a project whose subject is which role carries which policy"

  validation {
    condition     = can(regex("^[\\w+=,.@-]{1,32}$", var.role_name_prefix))
    error_message = "role_name_prefix must be 1-32 characters from the set IAM accepts for role names (letters, digits and _+=,.@-), leaving room for the generated suffix inside the 64 character limit."
  }
}
variable "role_policy_arns" {
  type        = list(string)
  default     = ["arn:aws:iam::aws:policy/service-role/AWS_ConfigRole"]
  description = "Managed policies attached to that role. One for_each attachment rather than one resource per policy, so the caller can add one without this module changing (rules.md B-7); toset is safe because these are literal strings in configuration and therefore known at plan time (rules.md B-8)"

  validation {
    condition     = alltrue([for arn in var.role_policy_arns : can(regex("^arn:aws[a-z-]*:iam::", arn))])
    error_message = "role_policy_arns must contain IAM policy ARNs."
  }
}
