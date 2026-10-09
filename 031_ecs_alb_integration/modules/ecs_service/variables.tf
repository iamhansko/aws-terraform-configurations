variable "service_name" {
  type        = string
  description = "Name of the ECS service"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,255}$", var.service_name))
    error_message = "service_name must be 1-255 characters of letters, digits, underscores and hyphens."
  }
}
variable "cluster_name" {
  type        = string
  description = "Name of the cluster the service runs in"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,255}$", var.cluster_name))
    error_message = "cluster_name must be 1-255 characters of letters, digits, underscores and hyphens."
  }
}
variable "task_family" {
  type        = string
  description = "Family of the task definition"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,255}$", var.task_family))
    error_message = "task_family must be 1-255 characters of letters, digits, underscores and hyphens."
  }
}
variable "container_name" {
  type        = string
  description = "Name of the container. The service's load_balancer block names it to pick which container's port to register, so it has to be the same string in both places"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9_-]{0,254}$", var.container_name))
    error_message = "container_name must start with a letter or digit and contain only letters, digits, underscores and hyphens."
  }
}
variable "image_uri" {
  type        = string
  description = "Full image reference the task pulls, tag included. Taken from the repository module rather than assembled here, so the push and the pull are one value (rules.md B-5)"

  validation {
    condition     = length(var.image_uri) > 0
    error_message = "image_uri must not be empty."
  }
}
variable "container_port" {
  type        = number
  default     = 80
  description = "Port the container listens on, used by the port mapping and the tasks' ingress rule"

  validation {
    condition     = var.container_port > 0 && var.container_port <= 65535
    error_message = "container_port must be a valid TCP port."
  }
}
variable "task_cpu" {
  type        = string
  default     = "256"
  description = "CPU units for the task"

  validation {
    condition     = contains(["256", "512", "1024", "2048", "4096", "8192", "16384"], var.task_cpu)
    error_message = "task_cpu must be one of the CPU sizes Fargate accepts: 256, 512, 1024, 2048, 4096, 8192 or 16384."
  }
}
variable "task_memory" {
  type        = string
  default     = "512"
  description = "Memory in MiB for the task. Fargate accepts only certain pairs of CPU and memory and rejects the rest at RegisterTaskDefinition"

  validation {
    condition     = can(regex("^[0-9]+$", var.task_memory)) && tonumber(var.task_memory) >= 512
    error_message = "task_memory must be a whole number of MiB, at least 512, which is the smallest value Fargate accepts."
  }
}
variable "desired_count" {
  type        = number
  default     = 1
  description = "Number of tasks the service keeps running"

  validation {
    condition     = var.desired_count >= 0
    error_message = "desired_count must be zero or greater."
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
  description = "Subnets the tasks' network interfaces are placed in"

  validation {
    condition     = length(var.subnet_ids) > 0
    error_message = "subnet_ids must contain at least one subnet."
  }

  validation {
    condition     = alltrue([for id in var.subnet_ids : can(regex("^subnet-[0-9a-f]+$", id))])
    error_message = "subnet_ids must contain valid subnet IDs (e.g. subnet-0123456789abcdef0)."
  }
}
variable "assign_public_ip" {
  type        = bool
  default     = true
  description = "Whether each task's network interface gets a public address. With the tasks in public subnets and no NAT gateway, this is their only route to ECR and CloudWatch Logs"
}
variable "target_group_arn" {
  type        = string
  description = "Target group the service registers its tasks into"

  validation {
    condition     = can(regex("^arn:aws(-[a-z]+)*:elasticloadbalancing:", var.target_group_arn))
    error_message = "target_group_arn must be an elasticloadbalancing target group ARN."
  }
}
variable "security_group_name" {
  type        = string
  default     = "ecs-svc-sg"
  description = "Name of the tasks' security group"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.security_group_name)) && !startswith(var.security_group_name, "sg-")
    error_message = "security_group_name must be 1-255 characters from the set AWS accepts for a security group name (a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*, no apostrophe) and must not start with \"sg-\", which EC2 reserves for security group IDs."
  }
}
variable "security_group_description" {
  type        = string
  default     = "Container port from the ALB inbound, ECR and CloudWatch Logs outbound"
  description = "Description attached to the tasks' security group. Changing it replaces the group, because EC2 has no API for modifying a description (rules.md F-1)"

  validation {
    condition     = length(var.security_group_description) > 0
    error_message = "security_group_description must not be empty."
  }

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.security_group_description))
    error_message = "security_group_description must be 1-255 characters from the set AWS accepts for a security group description: a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*. An apostrophe is NOT allowed - EC2 rejects CreateSecurityGroup with InvalidParameterValue, which otherwise only surfaces partway through an apply (rules.md F-1)."
  }
}
variable "ingress_source_security_groups" {
  type        = map(string)
  default     = {}
  description = "Security groups allowed inbound on container_port, keyed by a caller-chosen label. A map rather than a list because these IDs are another module's output, unknown until apply, and for_each needs statically known keys (rules.md B-8)"

  validation {
    condition     = alltrue([for label in keys(var.ingress_source_security_groups) : can(regex("^[a-zA-Z0-9._-]+$", label))])
    error_message = "ingress_source_security_groups keys appear in the rule descriptions and in the resource addresses, so each must be a non-empty string of letters, digits, dots, underscores or hyphens."
  }

  validation {
    condition     = alltrue([for id in values(var.ingress_source_security_groups) : can(regex("^sg-[0-9a-f]+$", id))])
    error_message = "ingress_source_security_groups must contain valid security group IDs (e.g. sg-0123456789abcdef0)."
  }
}
variable "iam_role_name_prefix" {
  type        = string
  default     = "ecs-task-execution-"
  description = "Prefix for the generated name of the task execution role. The _monolithic template let CloudFormation generate this name; name_prefix is how Terraform does the same"

  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_-]{1,38}$", var.iam_role_name_prefix))
    error_message = "iam_role_name_prefix must be 1-38 characters from the IAM name character set (letters, digits and +=,.@_-), leaving room for the suffix the provider appends within IAM's 64-character limit."
  }
}
variable "task_execution_role_policy_arns" {
  type        = list(string)
  default     = ["arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"]
  description = "Managed policies attached to the task execution role, as the _monolithic template attached them. AmazonECSTaskExecutionRolePolicy is what grants the ECR pull and the CloudWatch Logs write the awslogs driver needs"

  validation {
    condition     = alltrue([for arn in var.task_execution_role_policy_arns : can(regex("^arn:aws:iam::", arn))])
    error_message = "task_execution_role_policy_arns must contain valid IAM policy ARNs."
  }
}
variable "log_group_name" {
  type        = string
  default     = "/ecs/monitoring"
  description = "Log group the container's stdout is written to"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_./#-]{1,512}$", var.log_group_name))
    error_message = "log_group_name must be 1-512 characters of letters, digits and _ . / # -."
  }
}
variable "log_retention_in_days" {
  type        = number
  default     = 7
  description = "Days CloudWatch keeps the container log events. Null keeps them forever"

  validation {
    condition     = var.log_retention_in_days == null || contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], coalesce(var.log_retention_in_days, 1))
    error_message = "log_retention_in_days must be a value CloudWatch Logs accepts (1, 3, 5, 7, 14, 30, ...), or null."
  }
}
variable "log_stream_prefix" {
  type        = string
  default     = "ecs"
  description = "Prefix the awslogs driver puts in front of each stream name, which makes a stream read <prefix>/<container>/<task id>"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_.-]{1,128}$", var.log_stream_prefix))
    error_message = "log_stream_prefix must be 1-128 characters of letters, digits, dots, underscores or hyphens, and must not contain a colon or a slash."
  }
}
variable "wait_for_steady_state" {
  type        = bool
  default     = true
  description = "Whether apply waits for the service to reach a steady state, which is what CloudFormation did for an AWS::ECS::Service"
}
