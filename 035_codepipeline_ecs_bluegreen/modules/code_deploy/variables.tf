variable "application_name" {
  type        = string
  description = "Name of the CodeDeploy application. The pipeline's deploy action names it, and the pipeline role's policy is scoped to the ARN built from it"

  validation {
    condition     = can(regex("^[a-zA-Z0-9._+=,@-]{1,100}$", var.application_name))
    error_message = "application_name must be 1-100 characters from the set CodeDeploy accepts for an application name."
  }
}
variable "deployment_group_name" {
  type        = string
  description = "Name of the deployment group. The pipeline's deploy action names it, and the pipeline role's policy is scoped to application/group"

  validation {
    condition     = can(regex("^[a-zA-Z0-9._+=,@-]{1,100}$", var.deployment_group_name))
    error_message = "deployment_group_name must be 1-100 characters from the set CodeDeploy accepts for a deployment group name."
  }
}
variable "cluster_name" {
  type        = string
  description = "Cluster holding the service this group deploys"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,255}$", var.cluster_name))
    error_message = "cluster_name must be 1-255 characters of letters, digits, underscores and hyphens."
  }
}
variable "service_name" {
  type        = string
  description = "Service this group deploys. Taken by the caller from the service module's output, which is also what orders this module after the service - CodeDeploy validates at CreateDeploymentGroup that the service exists and that its deployment controller is CODE_DEPLOY"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,255}$", var.service_name))
    error_message = "service_name must be 1-255 characters of letters, digits, underscores and hyphens."
  }
}
variable "listener_arns" {
  type        = list(string)
  description = "Production listeners whose default rule CodeDeploy rewrites to shift traffic. One in this project"

  validation {
    condition     = length(var.listener_arns) > 0
    error_message = "listener_arns must contain at least one listener. With none, CodeDeploy has nothing to rewrite and there is no way for a deployment to move traffic."
  }
  validation {
    condition     = alltrue([for arn in var.listener_arns : can(regex("^arn:aws[a-zA-Z-]*:elasticloadbalancing:.*:listener/", arn))])
    error_message = "listener_arns must contain elasticloadbalancing listener ARNs."
  }
}
variable "blue_target_group_name" {
  type        = string
  description = "Name of the target group production starts on. A name rather than an ARN because that is what load_balancer_info takes"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{1,32}$", var.blue_target_group_name))
    error_message = "blue_target_group_name must be 32 characters or fewer of letters, digits and hyphens - a target group name, not an ARN."
  }
}
variable "green_target_group_name" {
  type        = string
  description = "Name of the other target group, which the replacement task set registers into"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{1,32}$", var.green_target_group_name))
    error_message = "green_target_group_name must be 32 characters or fewer of letters, digits and hyphens - a target group name, not an ARN."
  }
  validation {
    condition     = var.green_target_group_name != var.blue_target_group_name
    error_message = "green_target_group_name must differ from blue_target_group_name. CodeDeploy needs two distinct groups to swap between."
  }
}
variable "deployment_config_name" {
  type        = string
  default     = "CodeDeployDefault.ECSAllAtOnce"
  description = "Traffic shifting configuration, as the _monolithic template had it. All at once, so the whole of production moves in one step with no canary period - which is what makes the before and after visible in a single request"

  validation {
    condition     = startswith(var.deployment_config_name, "CodeDeployDefault.ECS") || can(regex("^[a-zA-Z0-9._+=,@-]{1,100}$", var.deployment_config_name))
    error_message = "deployment_config_name must be a deployment configuration name. For an ECS application it has to be an ECS one - a CodeDeployDefault.OneAtATime or similar EC2 configuration is rejected at CreateDeploymentGroup."
  }
}
variable "deployment_ready_action_on_timeout" {
  type        = string
  default     = "CONTINUE_DEPLOYMENT"
  description = "What happens when the replacement task set is healthy, as the _monolithic template had it"

  validation {
    condition     = contains(["CONTINUE_DEPLOYMENT", "STOP_DEPLOYMENT"], var.deployment_ready_action_on_timeout)
    error_message = "deployment_ready_action_on_timeout must be CONTINUE_DEPLOYMENT or STOP_DEPLOYMENT. STOP_DEPLOYMENT additionally needs a wait_time_in_minutes, and parks the deployment until someone approves it."
  }
}
variable "termination_wait_time_in_minutes" {
  type        = number
  default     = 0
  description = "Minutes the original task set is kept after traffic has shifted, as the _monolithic template had it. Zero means an instant rollback is not possible and that a listener rule still pointing at the old target group has nothing behind it"

  validation {
    condition     = var.termination_wait_time_in_minutes >= 0 && var.termination_wait_time_in_minutes <= 2880
    error_message = "termination_wait_time_in_minutes must be between 0 and 2880."
  }
}
variable "auto_rollback_events" {
  type        = list(string)
  default     = ["DEPLOYMENT_FAILURE", "DEPLOYMENT_STOP_ON_ALARM", "DEPLOYMENT_STOP_ON_REQUEST"]
  description = "Events that roll a deployment back, as the _monolithic template had them. DEPLOYMENT_STOP_ON_ALARM is in the list and cannot fire, because there is no alarm configuration on this group for it to watch"

  validation {
    condition     = length(var.auto_rollback_events) > 0
    error_message = "auto_rollback_events must not be empty while automatic rollback is enabled."
  }
  validation {
    condition     = alltrue([for event in var.auto_rollback_events : contains(["DEPLOYMENT_FAILURE", "DEPLOYMENT_STOP_ON_ALARM", "DEPLOYMENT_STOP_ON_REQUEST"], event)])
    error_message = "auto_rollback_events must contain only DEPLOYMENT_FAILURE, DEPLOYMENT_STOP_ON_ALARM or DEPLOYMENT_STOP_ON_REQUEST."
  }
}
variable "role_name_prefix" {
  type        = string
  description = "Prefix the CodeDeploy service role name is generated from, replacing the _monolithic template's CodeDeployRole plus a uuid-derived suffix"

  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_-]{1,38}$", var.role_name_prefix))
    error_message = "role_name_prefix must be 1-38 characters from the IAM role name character set, leaving room for the generated suffix inside IAM's 64 character limit."
  }
}
variable "create_deploy_policy" {
  type        = bool
  default     = true
  description = "Whether to create the inline policy. True, and turning it off means supplying an equivalent some other way - a deployment group whose role cannot call ModifyListener creates the replacement task set and then fails with traffic still on the old one (rules.md A-5)"
}
variable "artifact_bucket_arn" {
  type        = string
  description = "ARN of the pipeline's artifact store, which the policy's S3 statement is scoped to. CodeDeploy reads the appspec from there, so this is the only bucket it needs"

  validation {
    condition     = can(regex("^arn:aws[a-zA-Z-]*:s3:::", var.artifact_bucket_arn))
    error_message = "artifact_bucket_arn must be an S3 bucket ARN (e.g. arn:aws:s3:::my-bucket)."
  }
}
variable "task_execution_role_arn" {
  type        = string
  description = "The one role CodeDeploy is allowed to pass, which is the execution role named by the task definition it deploys"

  validation {
    condition     = can(regex("^arn:aws[a-zA-Z-]*:iam::[0-9]{12}:role/", var.task_execution_role_arn))
    error_message = "task_execution_role_arn must be an IAM role ARN."
  }
}
