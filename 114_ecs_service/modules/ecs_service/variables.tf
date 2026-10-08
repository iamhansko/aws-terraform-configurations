variable "name" {
  type        = string
  description = "Name of the ECS service, also used as the prefix of its three roles' generated names"

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
variable "region" {
  type        = string
  description = "Region the awslogs driver ships to. Passed in rather than read with a data source here, because this module is called with depends_on, which would defer that read to apply and leave the whole container definition unknown at plan (rules.md D-6)"

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
  description = "Private subnets the tasks are placed in"

  validation {
    condition     = length(var.subnet_ids) > 0 && alltrue([for id in var.subnet_ids : can(regex("^subnet-[0-9a-f]+$", id))])
    error_message = "subnet_ids must contain at least one valid subnet ID."
  }
}
variable "security_group_name" {
  type        = string
  default     = "ecs-service-sg"
  description = "Name of the tasks' security group, as the _monolithic template had it"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.security_group_name)) && !startswith(var.security_group_name, "sg-")
    error_message = "security_group_name must be 1-255 characters from the set AWS accepts for a security group name (no apostrophe) and must not start with \"sg-\" (rules.md F-1)."
  }
}
variable "ingress_source_security_groups" {
  type        = map(string)
  default     = {}
  description = "Security groups allowed to reach the container port, keyed by a caller-chosen label. A map rather than a list because these IDs are another module's output, unknown until apply, and for_each needs keys known at plan (rules.md B-8)"

  validation {
    condition     = alltrue([for label in keys(var.ingress_source_security_groups) : can(regex("^[a-zA-Z0-9._-]+$", label))])
    error_message = "ingress_source_security_groups keys are labels used in rule descriptions and resource addresses, so each must be letters, digits, dots, underscores or hyphens (rules.md F-1)."
  }
  validation {
    condition     = alltrue([for id in values(var.ingress_source_security_groups) : can(regex("^sg-[0-9a-f]+$", id))])
    error_message = "ingress_source_security_groups must contain valid security group IDs (e.g. sg-0123456789abcdef0)."
  }
}
variable "task_family" {
  type        = string
  default     = "nginx-td"
  description = "Task definition family, as the _monolithic template had it"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,255}$", var.task_family))
    error_message = "task_family must be 1-255 characters of letters, digits, hyphens and underscores."
  }
}
variable "task_cpu" {
  type        = string
  default     = "256"
  description = "Task CPU units, as the _monolithic template had it"

  validation {
    condition     = contains(["256", "512", "1024", "2048", "4096", "8192", "16384"], var.task_cpu)
    error_message = "task_cpu must be one of the Fargate CPU values: 256, 512, 1024, 2048, 4096, 8192 or 16384."
  }
}
variable "task_memory" {
  type        = string
  default     = "512"
  description = "Task memory in MiB, as the _monolithic template had it. Fargate accepts only certain memory values for each CPU value, and an invalid pair is rejected when the task definition is registered"

  validation {
    condition     = can(regex("^[0-9]+$", var.task_memory)) && tonumber(var.task_memory) >= 512
    error_message = "task_memory must be a whole number of MiB, at least 512."
  }
}
variable "container_name" {
  type        = string
  default     = "core"
  description = "Name of the container, as the _monolithic template had it. The service's load_balancer block names it, and both read it from here"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,255}$", var.container_name))
    error_message = "container_name must be 1-255 characters of letters, digits, hyphens and underscores."
  }
}
variable "container_image" {
  type        = string
  default     = "nginx"
  description = "Image the container runs. nginx with no tag, as the _monolithic template had it - which means latest from Docker Hub, pulled anonymously through the NAT gateway and subject to its rate limit"

  validation {
    condition     = length(var.container_image) > 0
    error_message = "container_image must not be empty."
  }
}
variable "container_port" {
  type        = number
  default     = 80
  description = "Port the container listens on"

  validation {
    condition     = var.container_port > 0 && var.container_port <= 65535
    error_message = "container_port must be a valid TCP port."
  }
}
variable "log_group_name" {
  type        = string
  description = "Log group the awslogs driver writes to. Taken from the module that subscribes it to Firehose, so the container writes to exactly the subscribed group (rules.md B-5)"

  validation {
    condition     = length(var.log_group_name) > 0
    error_message = "log_group_name must not be empty."
  }
}
variable "log_group_arn" {
  type        = string
  description = "ARN of that log group, for scoping the task role's ECS Exec logging permissions to it"

  validation {
    condition     = can(regex("^arn:aws[a-zA-Z-]*:logs:", var.log_group_arn))
    error_message = "log_group_arn must be a CloudWatch Logs log group ARN."
  }
}
variable "log_stream_prefix" {
  type        = string
  default     = "nginx"
  description = "awslogs stream prefix, as the _monolithic template had it. Streams are named <prefix>/<container>/<task id>"

  validation {
    condition     = length(var.log_stream_prefix) > 0
    error_message = "log_stream_prefix must not be empty."
  }
}
variable "desired_count" {
  type        = number
  default     = 2
  description = "Number of tasks, as the _monolithic template had it. Two, one per zone, is the smallest count availability_zone_rebalancing has anything to rebalance"

  validation {
    condition     = var.desired_count >= 0
    error_message = "desired_count must be zero or greater."
  }
}
variable "availability_zone_rebalancing" {
  type        = string
  default     = "ENABLED"
  description = "Whether ECS moves tasks to even out zones after an imbalance, as the _monolithic template had it"

  validation {
    condition     = contains(["ENABLED", "DISABLED"], var.availability_zone_rebalancing)
    error_message = "availability_zone_rebalancing must be ENABLED or DISABLED."
  }
}
variable "health_check_grace_period_seconds" {
  type        = number
  default     = 5
  description = "Seconds ECS ignores failing ALB health checks after a task starts, as the _monolithic template had it"

  validation {
    condition     = var.health_check_grace_period_seconds >= 0 && var.health_check_grace_period_seconds <= 2147483647
    error_message = "health_check_grace_period_seconds must be zero or greater."
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
variable "alternate_target_group_arn" {
  type        = string
  description = "Alternate target group named by the load balancer's advanced_configuration"

  validation {
    condition     = can(regex("^arn:aws[a-zA-Z-]*:elasticloadbalancing:.*:targetgroup/", var.alternate_target_group_arn))
    error_message = "alternate_target_group_arn must be an ELB target group ARN."
  }
}
variable "production_listener_rule_arn" {
  type        = string
  description = "Listener rule named by the load balancer's advanced_configuration as production_listener_rule"

  validation {
    condition     = can(regex("^arn:aws[a-zA-Z-]*:elasticloadbalancing:.*:listener-rule/", var.production_listener_rule_arn))
    error_message = "production_listener_rule_arn must be an ELB listener rule ARN."
  }
}
variable "wait_for_steady_state" {
  type        = bool
  default     = true
  description = "Whether apply waits for the service to reach a steady state. True, because that is what a CloudFormation AWS::ECS::Service does and so what the _monolithic stack did - and it is what turns a task that cannot pull its image into an apply failure instead of a service quietly cycling tasks"
}
