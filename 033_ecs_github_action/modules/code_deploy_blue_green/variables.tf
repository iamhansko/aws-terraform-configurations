variable "application_name" {
  type        = string
  default     = "ecs-codedeploy-app"
  description = "Name of the CodeDeploy application, as the _monolithic template named it. The workflow's deploy action names it"

  validation {
    condition     = can(regex("^[a-zA-Z0-9._+=,@-]{1,100}$", var.application_name))
    error_message = "application_name must be 1-100 characters from the set CodeDeploy accepts for an application name."
  }
}
variable "deployment_group_name" {
  type        = string
  default     = "ecs-codedeploy-dg"
  description = "Name of the deployment group, as the _monolithic template named it. The workflow's deploy action names it"

  validation {
    condition     = can(regex("^[a-zA-Z0-9._+=,@-]{1,100}$", var.deployment_group_name))
    error_message = "deployment_group_name must be 1-100 characters from the set CodeDeploy accepts for a deployment group name."
  }
}
variable "cluster_name" {
  type        = string
  description = "Name of the ECS cluster holding the service, taken from the cluster module's output (rules.md B-5)"

  validation {
    condition     = length(var.cluster_name) > 0
    error_message = "cluster_name must not be empty."
  }
}
variable "service_name" {
  type        = string
  description = "Name of the ECS service this group deploys. Taken from the service module's output, so the group and the service cannot name different things - CodeDeploy accepts a group pointing at a service that does not exist and fails at the first deployment (rules.md B-5)"

  validation {
    condition     = length(var.service_name) > 0
    error_message = "service_name must not be empty."
  }
}
variable "production_listener_arn" {
  type        = string
  description = "ARN of the ALB listener carrying production traffic. Rewriting its default action is how this group shifts traffic, which is why the load balancer module stops tracking that field (rules.md E-8)"

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:elasticloadbalancing:.*:listener/", var.production_listener_arn))
    error_message = "production_listener_arn must be an elasticloadbalancing listener ARN."
  }
}
variable "blue_target_group_name" {
  type        = string
  description = "Name of the first target group in the pair. CodeDeploy's target_group blocks take names rather than ARNs, so this comes from the load balancer module's name output (rules.md B-5)"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{1,32}$", var.blue_target_group_name))
    error_message = "blue_target_group_name must be 32 characters or fewer of letters, digits and hyphens."
  }
}
variable "green_target_group_name" {
  type        = string
  description = "Name of the second target group in the pair"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{1,32}$", var.green_target_group_name))
    error_message = "green_target_group_name must be 32 characters or fewer of letters, digits and hyphens."
  }

  validation {
    condition     = var.green_target_group_name != var.blue_target_group_name
    error_message = "green_target_group_name must differ from blue_target_group_name. CodeDeploy's pair has to name two distinct groups, and naming one twice is accepted at creation and then fails at the first deployment with nothing to swap to."
  }
}
variable "deployment_config_name" {
  type        = string
  default     = "CodeDeployDefault.ECSAllAtOnce"
  description = "Deployment configuration controlling how fast traffic shifts, as the _monolithic template had it. AllAtOnce moves the whole listener in one step, which is what makes the cutover visible in a single curl"

  validation {
    condition     = length(var.deployment_config_name) > 0
    error_message = "deployment_config_name must not be empty."
  }
  validation {
    condition     = can(regex("^CodeDeployDefault\\.ECS", var.deployment_config_name)) || !startswith(var.deployment_config_name, "CodeDeployDefault.")
    error_message = "deployment_config_name must be one of the ECS CodeDeployDefault configurations (CodeDeployDefault.ECS*) or a custom configuration name. The EC2 and Lambda defaults are rejected for an ECS compute platform."
  }
}
variable "deployment_ready_action_on_timeout" {
  type        = string
  default     = "CONTINUE_DEPLOYMENT"
  description = "What happens once the replacement task set is ready, as the _monolithic template had it. CONTINUE_DEPLOYMENT shifts traffic immediately; STOP_DEPLOYMENT waits for a manual reroute and then uses deployment_ready_wait_time_in_minutes"

  validation {
    condition     = contains(["CONTINUE_DEPLOYMENT", "STOP_DEPLOYMENT"], var.deployment_ready_action_on_timeout)
    error_message = "deployment_ready_action_on_timeout must be CONTINUE_DEPLOYMENT or STOP_DEPLOYMENT."
  }
}
variable "deployment_ready_wait_time_in_minutes" {
  type        = number
  default     = 60
  description = "How long CodeDeploy waits for a manual reroute before timing out. Only sent when deployment_ready_action_on_timeout is STOP_DEPLOYMENT, because CodeDeploy rejects it alongside CONTINUE_DEPLOYMENT"

  validation {
    condition     = var.deployment_ready_wait_time_in_minutes >= 0 && var.deployment_ready_wait_time_in_minutes <= 2880
    error_message = "deployment_ready_wait_time_in_minutes must be between 0 and 2880 (48 hours)."
  }
}
variable "termination_wait_time_in_minutes" {
  type        = number
  default     = 0
  description = "How long the original task set keeps running after traffic has shifted, as the _monolithic template had it. Zero means an instant rollback is not possible, and that two task sets never overlap for longer than the cutover"

  validation {
    condition     = var.termination_wait_time_in_minutes >= 0 && var.termination_wait_time_in_minutes <= 2880
    error_message = "termination_wait_time_in_minutes must be between 0 and 2880 (48 hours)."
  }
}
variable "auto_rollback_enabled" {
  type        = bool
  default     = true
  description = "Whether a failed deployment rolls back to the original task set, as the _monolithic template had it"
}
variable "auto_rollback_events" {
  type = list(string)
  default = [
    "DEPLOYMENT_FAILURE",
    "DEPLOYMENT_STOP_ON_ALARM",
    "DEPLOYMENT_STOP_ON_REQUEST",
  ]
  description = "Which events trigger a rollback, as the _monolithic template listed them"

  validation {
    condition     = alltrue([for event in var.auto_rollback_events : contains(["DEPLOYMENT_FAILURE", "DEPLOYMENT_STOP_ON_ALARM", "DEPLOYMENT_STOP_ON_REQUEST"], event)])
    error_message = "auto_rollback_events entries must each be DEPLOYMENT_FAILURE, DEPLOYMENT_STOP_ON_ALARM or DEPLOYMENT_STOP_ON_REQUEST."
  }
  validation {
    condition     = !var.auto_rollback_enabled || length(var.auto_rollback_events) > 0
    error_message = "auto_rollback_events must list at least one event while auto_rollback_enabled is true, otherwise rollback is enabled with nothing to trigger it."
  }
}
variable "service_role_policy_arns" {
  type        = list(string)
  default     = ["arn:aws:iam::aws:policy/AWSCodeDeployRoleForECS"]
  description = "IAM managed policy ARNs attached to the CodeDeploy service role, as the _monolithic template attached them. AWSCodeDeployRoleForECS is AWS's service role policy for ECS blue/green and is already scoped to that work (rules.md A-5)"

  validation {
    condition     = alltrue([for arn in var.service_role_policy_arns : can(regex("^arn:aws:iam::", arn))])
    error_message = "service_role_policy_arns must contain valid IAM policy ARNs."
  }
  validation {
    condition     = length(var.service_role_policy_arns) > 0
    error_message = "service_role_policy_arns must contain at least one policy. CodeDeploy validates the role at CreateDeploymentGroup and a role with no policy fails there rather than at the first deployment."
  }
}
