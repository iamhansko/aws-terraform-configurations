variable "name" {
  type        = string
  description = "Prefix of the functions, their target groups and the event rules. At most 23 characters, because the longest target group name is this plus -shutdown and ELB allows 32"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,22}$", var.name))
    error_message = "name must be 2-23 characters of lowercase letters, digits and hyphens."
  }
}
variable "source_zip_path" {
  type        = string
  description = "Path of the zipped admin_lambda directory, which all seven functions share. Zipped by the caller, so the archive is read at plan even though this module is ordered after the network (rules.md D-6)"

  validation {
    condition     = endswith(var.source_zip_path, ".zip")
    error_message = "source_zip_path must point at a .zip file."
  }
}
variable "source_code_hash" {
  type        = string
  description = "Base64 SHA-256 of that zip, which is what redeploys the functions when the code changes"

  validation {
    condition     = length(var.source_code_hash) > 0
    error_message = "source_code_hash must not be empty."
  }
}
variable "runtime" {
  type        = string
  default     = "python3.12"
  description = "Runtime of the functions, python3.12 as the blueprint had it"

  validation {
    condition     = can(regex("^python3\\.(1[2-9]|[2-9][0-9])$", var.runtime))
    error_message = "runtime must be python3.12 or newer."
  }
}
variable "timeout" {
  type        = number
  default     = 60
  description = "Timeout of each function in seconds, 60 as the blueprint had it"

  validation {
    condition     = var.timeout >= 1 && var.timeout <= 900
    error_message = "timeout must be between 1 and 900 seconds."
  }
}
variable "log_retention_days" {
  type        = number
  default     = 731
  description = "Retention of the functions' log groups"

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be one of the retention periods CloudWatch Logs accepts."
  }
}
variable "function_policy_arns" {
  type = list(string)
  default = [
    "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole",
    "arn:aws:iam::aws:policy/AutoScalingFullAccess",
  ]
  description = "Managed policies on the functions' role, the blueprint's two - kept as it had them (rules.md A-5). AutoScalingFullAccess is broader than the two calls the functions make on the group, DescribeAutoScalingGroups and SetDesiredCapacity; narrowing it means a policy with those two, the second scoped to the group's ARN"

  validation {
    condition     = alltrue([for arn in var.function_policy_arns : can(regex("^arn:aws[a-z-]*:iam::", arn))])
    error_message = "function_policy_arns must contain IAM policy ARNs."
  }
}
variable "auto_scaling_group_name" {
  type        = string
  description = "The GPU Auto Scaling group the functions read and resize"

  validation {
    condition     = length(var.auto_scaling_group_name) > 0
    error_message = "auto_scaling_group_name must not be empty."
  }
}
variable "cluster_name" {
  type        = string
  description = "ECS cluster the service is in"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,255}$", var.cluster_name))
    error_message = "cluster_name must be a valid ECS cluster name."
  }
}
variable "cluster_arn" {
  type        = string
  description = "ARN of that cluster, which the task state change rule matches on"

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:ecs:[^:]+:[0-9]{12}:cluster/", var.cluster_arn))
    error_message = "cluster_arn must be an ECS cluster ARN."
  }
}
variable "service_name" {
  type        = string
  description = "ECS service the functions read and, for a scale-up, update"

  validation {
    condition     = length(var.service_name) > 0
    error_message = "service_name must not be empty."
  }
}
variable "listener_arn" {
  type        = string
  description = "HTTPS listener the routes are added to"

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:elasticloadbalancing:[^:]+:[0-9]{12}:listener/app/", var.listener_arn))
    error_message = "listener_arn must be the ARN of an Application Load Balancer listener."
  }
}
variable "cognito_user_pool_arn" {
  type        = string
  description = "User pool the routes authenticate against"

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:cognito-idp:", var.cognito_user_pool_arn))
    error_message = "cognito_user_pool_arn must be a Cognito user pool ARN."
  }
}
variable "cognito_user_pool_client_id" {
  type        = string
  description = "App client the load balancer authenticates with"

  validation {
    condition     = length(var.cognito_user_pool_client_id) > 0
    error_message = "cognito_user_pool_client_id must not be empty."
  }
}
variable "cognito_user_pool_domain" {
  type        = string
  description = "Prefix of the user pool's hosted UI domain"

  validation {
    condition     = length(var.cognito_user_pool_domain) > 0
    error_message = "cognito_user_pool_domain must not be empty."
  }
}
variable "logout_redirect_url" {
  type        = string
  description = "Where /signout sends the browser after clearing the load balancer's session cookies - Cognito's logout endpoint for the client, returning to the application"

  validation {
    condition     = startswith(var.logout_redirect_url, "https://")
    error_message = "logout_redirect_url must be an https URL."
  }
}
