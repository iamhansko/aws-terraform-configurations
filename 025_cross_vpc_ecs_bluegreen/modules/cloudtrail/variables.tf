variable "trail_name" {
  type        = string
  description = "Name of the trail. Account and region wide, and also assembled into the trail ARN the bucket policy conditions name - the policy cannot reference the trail resource, because the trail depends on the policy"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9._-]{2,127}$", var.trail_name))
    error_message = "trail_name must be 3-128 characters, start with a letter or digit, and contain only letters, digits, dots, underscores and hyphens."
  }
}
variable "region" {
  type        = string
  description = "Region the trail ARN is built from. Passed in rather than read with a data source, which a module carrying depends_on would defer to apply (rules.md B-6, D-6)"

  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]$", var.region))
    error_message = "region must be an AWS region code (e.g. ap-northeast-2)."
  }
}
variable "account_id" {
  type        = string
  description = "Account ID, used in the trail ARN and in the object prefix the write statement allows"

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be a 12-digit AWS account ID."
  }
}
variable "partition" {
  type        = string
  description = "ARN partition"

  validation {
    condition     = can(regex("^aws[a-z-]*$", var.partition))
    error_message = "partition must be an AWS partition name (e.g. aws, aws-cn, aws-us-gov)."
  }
}
variable "logs_bucket_prefix" {
  type        = string
  description = "Prefix for the generated trail log bucket name"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,40}$", var.logs_bucket_prefix))
    error_message = "logs_bucket_prefix must be 2-41 characters of lowercase letters, digits, dots and hyphens, leaving room for the generated suffix inside the 63 character bucket name limit."
  }
}
variable "data_resource_object_arns" {
  type        = list(string)
  description = "Object ARNs whose writes the trail records. One per application stack artefact, built in the stack module. Object-level rather than bucket-level: a bucket-level selector records the pipeline's own artefact writes too, and each of those would start another pipeline run"

  validation {
    condition     = length(var.data_resource_object_arns) > 0
    error_message = "data_resource_object_arns must contain at least one ARN: a trail with an empty data resource selector records nothing, so no EventBridge rule ever fires and no pipeline ever starts - with nothing failing to say so."
  }
  validation {
    condition     = alltrue([for arn in var.data_resource_object_arns : can(regex("^arn:aws[a-z-]*:s3:::", arn))])
    error_message = "data_resource_object_arns must contain S3 object ARNs (e.g. arn:aws:s3:::bucket/artifact.zip)."
  }
}
variable "include_management_events" {
  type        = bool
  description = "Whether the trail also records management events. False here: nothing in this project reads them, and the _monolithic template left the default on - which records every API call in the region in order to notice two PutObject calls"
}
variable "force_destroy" {
  type        = bool
  description = "Whether terraform destroy empties the log bucket before deleting it. True, because CloudTrail writes into it continuously and S3 refuses to delete a non-empty bucket"
}
