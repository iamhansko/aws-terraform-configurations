variable "name" {
  type        = string
  description = "Name of the pipeline. Read twice rather than written twice: the resource is named from it and the role's policy builds the pipeline ARN from it, because referencing the resource's own ARN inside the policy that the resource depends on would be a cycle (rules.md B-5)"

  validation {
    condition     = can(regex("^[A-Za-z0-9.@_-]{1,100}$", var.name))
    error_message = "name must be 1-100 characters of letters, digits, dots, at signs, underscores and hyphens, which is what CodePipeline accepts."
  }
}
variable "region" {
  type        = string
  description = "Region the policy's assembled ARNs are built from. Passed in rather than read from a data source, so this module has no data source to be deferred to apply (rules.md D-6)"

  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]$", var.region))
    error_message = "region must be an AWS region code such as ap-northeast-2."
  }
}
variable "account_id" {
  type        = string
  description = "Account the policy's assembled ARNs are built from"

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be a 12-digit AWS account ID."
  }
}
variable "partition" {
  type        = string
  default     = "aws"
  description = "ARN partition the policy's assembled ARNs are built from"

  validation {
    condition     = can(regex("^aws[a-zA-Z-]*$", var.partition))
    error_message = "partition must be an AWS partition such as aws, aws-cn or aws-us-gov."
  }
}
variable "pipeline_type" {
  type        = string
  default     = "V2"
  description = "Pipeline type, as the _monolithic template had it"

  validation {
    condition     = contains(["V1", "V2"], var.pipeline_type)
    error_message = "pipeline_type must be V1 or V2."
  }
}
variable "role_name_prefix" {
  type        = string
  description = "Prefix the pipeline service role name is generated from, replacing the _monolithic template's CodePipelineRole plus a uuid-derived suffix"

  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_-]{1,38}$", var.role_name_prefix))
    error_message = "role_name_prefix must be 1-38 characters from the IAM role name character set, leaving room for the generated suffix inside IAM's 64 character limit."
  }
}
variable "create_pipeline_policy" {
  type        = bool
  default     = true
  description = "Whether to create the inline policy. True, and turning it off means supplying an equivalent some other way - the first execution starts during apply, so a role with no policy fails immediately rather than later (rules.md A-5)"
}
variable "allow_self_start" {
  type        = bool
  default     = false
  description = "Whether the pipeline role may start its own pipeline. The _monolithic template granted this and nothing needed it: the EventBridge rule has its own role for that. Off by default, available for a release started from the console under this role"
}
variable "source_bucket_name" {
  type        = string
  description = "Bucket the source action reads. Taken from the bucket module so that the bastion's upload target and this are one value (rules.md B-5)"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.source_bucket_name))
    error_message = "source_bucket_name must be a valid S3 bucket name."
  }
}
variable "source_bucket_arn" {
  type        = string
  description = "ARN of that bucket, which the policy's read-only S3 statement is scoped to"

  validation {
    condition     = can(regex("^arn:aws[a-zA-Z-]*:s3:::", var.source_bucket_arn))
    error_message = "source_bucket_arn must be an S3 bucket ARN (e.g. arn:aws:s3:::my-bucket)."
  }
}
variable "source_object_key" {
  type        = string
  default     = "src.zip"
  description = "Key the source action reads, which has to be the key the bastion uploads and the key the EventBridge pattern matches (rules.md B-5)"

  validation {
    condition     = can(regex("^[A-Za-z0-9!._*'()-]+\\.zip$", var.source_object_key))
    error_message = "source_object_key must be a single .zip filename. A CodePipeline S3 source action requires a zip archive and rejects anything else at the source stage."
  }
}
variable "artifact_bucket_name" {
  type        = string
  description = "Bucket the pipeline stores its artefacts in, which is a different bucket from the source"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.artifact_bucket_name))
    error_message = "artifact_bucket_name must be a valid S3 bucket name."
  }
}
variable "artifact_bucket_arn" {
  type        = string
  description = "ARN of the artifact store, which the policy's read-write S3 statement is scoped to"

  validation {
    condition     = can(regex("^arn:aws[a-zA-Z-]*:s3:::", var.artifact_bucket_arn))
    error_message = "artifact_bucket_arn must be an S3 bucket ARN (e.g. arn:aws:s3:::my-bucket)."
  }
}
variable "code_build_project_name" {
  type        = string
  description = "Build project the build action runs"

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9_-]{1,254}$", var.code_build_project_name))
    error_message = "code_build_project_name must be 2-255 characters of letters, digits, underscores and hyphens."
  }
}
variable "code_build_project_arn" {
  type        = string
  description = "ARN of that project, which the policy's codebuild statement is scoped to"

  validation {
    condition     = can(regex("^arn:aws[a-zA-Z-]*:codebuild:", var.code_build_project_arn))
    error_message = "code_build_project_arn must be a CodeBuild project ARN."
  }
}
variable "code_deploy_application_name" {
  type        = string
  description = "CodeDeploy application the deploy action names, also used to build the application and deployment group ARNs the policy is scoped to"

  validation {
    condition     = can(regex("^[a-zA-Z0-9._+=,@-]{1,100}$", var.code_deploy_application_name))
    error_message = "code_deploy_application_name must be 1-100 characters from the set CodeDeploy accepts for an application name."
  }
}
variable "code_deploy_deployment_group_name" {
  type        = string
  description = "Deployment group the deploy action names. The group's declared name, not the generated deployment group id the _monolithic template passed here - which validate and plan both accept and the stage then fails on"

  validation {
    condition     = can(regex("^[a-zA-Z0-9._+=,@-]{1,100}$", var.code_deploy_deployment_group_name))
    error_message = "code_deploy_deployment_group_name must be 1-100 characters from the set CodeDeploy accepts for a deployment group name. A deployment group id is a hyphenated uuid and would pass this check, so compare it against the deployment group module's deployment_group_name output rather than its deployment_group_id."
  }
}
variable "deployment_config_name" {
  type        = string
  default     = "CodeDeployDefault.ECSAllAtOnce"
  description = "Deployment configuration the deploy action will use, taken from the CodeDeploy module so the ARN this policy allows GetDeploymentConfig on is the configuration the group actually has (rules.md B-5)"

  validation {
    condition     = can(regex("^[a-zA-Z0-9._+=,@-]{1,100}$", var.deployment_config_name))
    error_message = "deployment_config_name must be a deployment configuration name."
  }
}
