variable "trail_name" {
  type        = string
  description = "Name of the trail. The bucket policy's aws:SourceArn conditions are built from it, so the two cannot be allowed to diverge - which is why it is a variable read twice rather than a literal written twice (rules.md B-5)"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9._-]{2,127}$", var.trail_name))
    error_message = "trail_name must be 3-128 characters of letters, digits, dots, underscores and hyphens, starting with a letter or digit."
  }
}
variable "region" {
  type        = string
  description = "Region the trail ARN in the bucket policy is built from. Passed in rather than read from a data source, so this module has no data source to be deferred to apply (rules.md D-6)"

  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]$", var.region))
    error_message = "region must be an AWS region code such as ap-northeast-2."
  }
}
variable "account_id" {
  type        = string
  description = "Account the trail ARN and the log object prefix in the bucket policy are built from"

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be a 12-digit AWS account ID."
  }
}
variable "partition" {
  type        = string
  default     = "aws"
  description = "ARN partition the trail ARN is built from"

  validation {
    condition     = can(regex("^aws[a-zA-Z-]*$", var.partition))
    error_message = "partition must be an AWS partition such as aws, aws-cn or aws-us-gov."
  }
}
variable "logs_bucket_prefix" {
  type        = string
  description = "Prefix the log bucket name is generated from. A prefix rather than a fixed name because S3 bucket names are globally unique"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,36}$", var.logs_bucket_prefix))
    error_message = "logs_bucket_prefix must be 2-37 characters of lowercase letters, digits, dots and hyphens starting with a letter or digit, leaving room for the generated suffix inside the 63 character bucket name limit."
  }
}
variable "data_resource_object_arns" {
  type        = list(string)
  description = "Object-level S3 ARNs whose writes are recorded. One in this project: the pipeline's source archive, assembled in the bucket module so the bucket and the key stay together (rules.md B-5)"

  validation {
    condition     = length(var.data_resource_object_arns) > 0
    error_message = "data_resource_object_arns must not be empty. A trail with no data resource records no object writes at all, which leaves the EventBridge rule correct and permanently silent - management events never include an object PUT."
  }
  validation {
    condition     = alltrue([for arn in var.data_resource_object_arns : can(regex("^arn:aws[a-zA-Z-]*:s3:::[a-z0-9][a-z0-9.-]*/.+$", arn))])
    error_message = "data_resource_object_arns must be object-level S3 ARNs including a key, such as arn:aws:s3:::my-bucket/src.zip. A bucket-level ARN is accepted by CloudTrail and records every write in the bucket, each of which would start another pipeline execution."
  }
}
variable "include_management_events" {
  type        = bool
  default     = false
  description = "Whether the trail also records management events. False, where the provider's default and therefore the _monolithic template's behaviour is true - nothing here reads a management event, and leaving it on means a log file for every API call in the region in order to notice one object write"
}
variable "force_destroy" {
  type        = bool
  default     = true
  description = "Whether to delete the log bucket together with the objects in it. True because CloudTrail writes digest files on a timer, so this bucket is never empty by the time a destroy reaches it. What it discards is the audit log itself, which for a trail that exists only to make an EventBridge rule fire is the right trade"
}
