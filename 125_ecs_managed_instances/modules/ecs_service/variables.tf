variable "name" {
  type        = string
  description = "Name of the ECS service, also the prefix of its roles' generated names"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,255}$", var.name))
    error_message = "name must be 1-255 characters of letters, digits, hyphens and underscores."
  }
}
variable "cluster_name" {
  type        = string
  description = "Name of the ECS cluster the service runs in"

  validation {
    condition     = length(var.cluster_name) > 0
    error_message = "cluster_name must not be empty."
  }
}
variable "capacity_provider_name" {
  type        = string
  description = "Managed instances capacity provider the service places through"

  validation {
    condition     = length(var.capacity_provider_name) > 0
    error_message = "capacity_provider_name must not be empty."
  }
}
variable "region" {
  type        = string
  description = "Region the awslogs driver ships to. Passed in rather than read with a data source here, because this module is called with depends_on, which would defer that read to apply and leave the container definition unknown at plan (rules.md D-6)"

  validation {
    condition     = can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]$", var.region))
    error_message = "region must be a region code such as ap-northeast-2."
  }
}
variable "vpc_id" {
  type        = string
  description = "VPC the tasks' security group is created in"

  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must be a valid VPC ID (e.g. vpc-0123456789abcdef0)."
  }
}
variable "subnet_ids" {
  type        = list(string)
  description = "Private subnets the tasks' ENIs are placed in"

  validation {
    condition     = length(var.subnet_ids) > 0 && alltrue([for id in var.subnet_ids : can(regex("^subnet-[0-9a-f]+$", id))])
    error_message = "subnet_ids must contain at least one valid subnet ID."
  }
}
variable "security_group_name" {
  type        = string
  description = "Name of the tasks' security group. The _monolithic template let EC2 generate one"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.security_group_name)) && !startswith(var.security_group_name, "sg-")
    error_message = "security_group_name must be 1-255 characters from the set AWS accepts for a security group name (no apostrophe) and must not start with \"sg-\" (rules.md F-1)."
  }
}
variable "ingress_source_security_groups" {
  type        = map(string)
  default     = {}
  description = "Security groups allowed to reach the container port, keyed by a caller-chosen label. A map because the IDs are other modules' outputs, unknown until apply (rules.md B-8)"

  validation {
    condition     = alltrue([for label in keys(var.ingress_source_security_groups) : can(regex("^[a-zA-Z0-9._-]+$", label))])
    error_message = "ingress_source_security_groups keys are labels used in rule descriptions and resource addresses, so each must be letters, digits, dots, underscores or hyphens (rules.md F-1)."
  }
  validation {
    condition     = alltrue([for id in values(var.ingress_source_security_groups) : can(regex("^sg-[0-9a-f]+$", id))])
    error_message = "ingress_source_security_groups must contain valid security group IDs."
  }
}
variable "extra_security_group_ids" {
  type        = list(string)
  default     = []
  description = "Further security groups the tasks carry, such as an EFS client group. The module does not know what they are for (rules.md B-6). A list is safe here because it is not iterated with for_each"

  validation {
    condition     = alltrue([for id in var.extra_security_group_ids : can(regex("^sg-[0-9a-f]+$", id))])
    error_message = "extra_security_group_ids must contain valid security group IDs."
  }
}
variable "task_family" {
  type        = string
  description = "Task definition family"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,255}$", var.task_family))
    error_message = "task_family must be 1-255 characters of letters, digits, hyphens and underscores."
  }
}
variable "task_cpu" {
  type        = number
  description = "Task CPU units. Has to fit on an instance in the capacity provider's vCPU range, or the task stays PROVISIONING"

  validation {
    condition     = var.task_cpu >= 128
    error_message = "task_cpu must be at least 128 CPU units."
  }
}
variable "task_memory" {
  type        = number
  description = "Task memory in MiB. Has to fit on an instance in the capacity provider's memory range, after the agent's own reservation"

  validation {
    condition     = var.task_memory >= 128
    error_message = "task_memory must be at least 128 MiB."
  }
}
variable "container_name" {
  type        = string
  description = "Name of the container. The service's load_balancer block names it, and both read it from here"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,255}$", var.container_name))
    error_message = "container_name must be 1-255 characters of letters, digits, hyphens and underscores."
  }
}
variable "container_image" {
  type        = string
  description = "Image the container runs"

  validation {
    condition     = length(var.container_image) > 0
    error_message = "container_image must not be empty."
  }
}
variable "container_port" {
  type        = number
  description = "Port the container listens on"

  validation {
    condition     = var.container_port > 0 && var.container_port <= 65535
    error_message = "container_port must be a valid TCP port."
  }
}
variable "secret_arn" {
  type        = string
  default     = null
  description = "Secrets Manager secret the secrets entries read from"

  validation {
    condition     = var.secret_arn == null || can(regex("^arn:aws[a-zA-Z-]*:secretsmanager:", var.secret_arn))
    error_message = "secret_arn must be a Secrets Manager secret ARN, or null."
  }
}
variable "secrets" {
  type        = map(string)
  default     = {}
  description = "Environment variables resolved from secret_arn when the task starts, as a map of variable name to JSON key in the secret"

  validation {
    condition     = alltrue([for name in keys(var.secrets) : can(regex("^[A-Za-z_][A-Za-z0-9_]*$", name))])
    error_message = "secrets keys must be valid environment variable names."
  }
  validation {
    # A pair constraint (rules.md B-1): entries with no secret to read from would register a task definition
    # whose valueFrom is ":KEY::", which ECS accepts and every task then fails to start on.
    condition     = length(var.secrets) == 0 || var.secret_arn != null
    error_message = "secret_arn must be set when secrets is not empty."
  }
}
variable "container_health_check" {
  type = object({
    command      = list(string)
    interval     = optional(number, 30)
    timeout      = optional(number, 5)
    retries      = optional(number, 3)
    start_period = optional(number, 0)
  })
  default     = null
  description = "Container health check. Null leaves the container without one, which leaves health entirely to the ALB"
}
variable "efs_volume" {
  type = object({
    name             = string
    file_system_id   = string
    file_system_arn  = string
    access_point_id  = string
    access_point_arn = string
    container_path   = string
  })
  default     = null
  description = "EFS volume to mount through an access point with IAM authorization. Setting it also creates the task role that authorization checks. Null mounts nothing"
}
variable "log_group_name" {
  type        = string
  description = "Log group the container writes to. A literal path, so two copies of this project in one account collide on it"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_./#-]{1,512}$", var.log_group_name))
    error_message = "log_group_name must be 1-512 characters of letters, digits and _ . / # -."
  }
}
variable "log_retention_in_days" {
  type        = number
  default     = 30
  description = "Days CloudWatch keeps the container's events, as the _monolithic template had it"

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_in_days)
    error_message = "log_retention_in_days must be a value CloudWatch Logs accepts."
  }
}
variable "target_group_arn" {
  type        = string
  description = "Target group the tasks are registered into"

  validation {
    condition     = can(regex("^arn:aws[a-zA-Z-]*:elasticloadbalancing:.*:targetgroup/", var.target_group_arn))
    error_message = "target_group_arn must be an ELB target group ARN."
  }
}
variable "desired_count" {
  type        = number
  default     = 1
  description = "Number of tasks"

  validation {
    condition     = var.desired_count >= 0
    error_message = "desired_count must be zero or greater."
  }
}
variable "health_check_grace_period_seconds" {
  type        = number
  default     = null
  description = "Seconds ECS ignores failing ALB health checks after a task starts. Null leaves ECS's default of none"

  validation {
    condition     = var.health_check_grace_period_seconds == null || coalesce(var.health_check_grace_period_seconds, 0) >= 0
    error_message = "health_check_grace_period_seconds must be zero or greater, or null."
  }
}
variable "deployment_maximum_percent" {
  type        = number
  default     = 200
  description = "Upper bound on running tasks during a deployment, as a percentage of desired_count"

  validation {
    condition     = var.deployment_maximum_percent >= 100
    error_message = "deployment_maximum_percent must be at least 100."
  }
}
variable "deployment_minimum_healthy_percent" {
  type        = number
  default     = 100
  description = "Lower bound on healthy tasks during a deployment, as a percentage of desired_count"

  validation {
    condition     = var.deployment_minimum_healthy_percent >= 0 && var.deployment_minimum_healthy_percent <= 100
    error_message = "deployment_minimum_healthy_percent must be between 0 and 100."
  }
}
variable "wait_for_steady_state" {
  type        = bool
  default     = true
  description = "Whether apply waits for the service to stabilise, which is what CloudFormation did for the _monolithic stack"
}
