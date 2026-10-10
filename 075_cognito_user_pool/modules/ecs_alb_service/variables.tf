variable "name" {
  type        = string
  description = "Base name of the service and its security groups (<name>-ecs-service, <name>-alb-sg, <name>-ecs-service-sg)"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{1,200}$", var.name))
    error_message = "name must be 1-200 characters of letters, digits and hyphens, so every name derived from it stays valid (rules.md F-1)."
  }
}
variable "region" {
  type        = string
  description = "Region the awslogs driver ships to. Passed in rather than read with a data source here, because this module is called with depends_on, which would defer that read to apply (rules.md D-6)"

  validation {
    condition     = can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]$", var.region))
    error_message = "region must be a region code such as ap-northeast-2."
  }
}
variable "vpc_id" {
  type        = string
  description = "VPC the target group and security groups are created in"

  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must be a valid VPC ID."
  }
}
variable "vpc_cidr_block" {
  type        = string
  description = "CIDR block of the VPC. The load balancer's only egress rule is to the container port inside it"

  validation {
    condition     = can(cidrhost(var.vpc_cidr_block, 0))
    error_message = "vpc_cidr_block must be a valid IPv4 CIDR block."
  }
}
variable "internal" {
  type        = bool
  description = "Whether the load balancer is internal. Its subnets have to match: public for internet-facing, private for internal"
}
variable "load_balancer_subnet_ids" {
  type        = list(string)
  description = "Subnets the load balancer is placed in. At least two, in different zones - ELB's own requirement"

  validation {
    condition     = length(var.load_balancer_subnet_ids) >= 2 && alltrue([for id in var.load_balancer_subnet_ids : can(regex("^subnet-[0-9a-f]+$", id))])
    error_message = "load_balancer_subnet_ids must contain at least two valid subnet IDs."
  }
}
variable "task_subnet_ids" {
  type        = list(string)
  description = "Private subnets the tasks' network interfaces are placed in"

  validation {
    condition     = length(var.task_subnet_ids) > 0 && alltrue([for id in var.task_subnet_ids : can(regex("^subnet-[0-9a-f]+$", id))])
    error_message = "task_subnet_ids must contain at least one valid subnet ID."
  }
}
variable "ingress_cidr_blocks" {
  type        = list(string)
  default     = []
  description = "CIDR blocks admitted on the listener port"

  validation {
    condition     = alltrue([for cidr in var.ingress_cidr_blocks : can(cidrhost(cidr, 0))])
    error_message = "ingress_cidr_blocks must contain valid CIDR blocks."
  }
}
variable "ingress_prefix_list_ids" {
  type        = list(string)
  default     = []
  description = "Managed prefix lists admitted on the listener port, e.g. CloudFront's origin-facing list. Prefix list entries count against the group's rule quota, so the CloudFront list belongs only on a load balancer CloudFront can reach"

  validation {
    condition     = alltrue([for id in var.ingress_prefix_list_ids : can(regex("^pl-[0-9a-f]+$", id))])
    error_message = "ingress_prefix_list_ids must contain valid managed prefix list IDs."
  }
}
variable "listener_port" {
  type        = number
  default     = 80
  description = "Port the HTTP listener accepts on, as the _monolithic template had it"

  validation {
    condition     = var.listener_port > 0 && var.listener_port <= 65535
    error_message = "listener_port must be a valid TCP port."
  }
}
variable "idle_timeout_seconds" {
  type        = number
  default     = 60
  description = "Seconds an idle connection is kept open, as the _monolithic template had it. A websocket with no traffic for this long is closed by the load balancer"

  validation {
    condition     = var.idle_timeout_seconds >= 1 && var.idle_timeout_seconds <= 4000
    error_message = "idle_timeout_seconds must be between 1 and 4000."
  }
}
variable "health_check_path" {
  type        = string
  default     = "/"
  description = "Path the target group health checks, as the _monolithic template had it"

  validation {
    condition     = startswith(var.health_check_path, "/")
    error_message = "health_check_path must start with /."
  }
}
variable "cluster_name" {
  type        = string
  description = "ECS cluster the service runs in"

  validation {
    condition     = length(var.cluster_name) > 0
    error_message = "cluster_name must not be empty."
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
  default     = 1024
  description = "Task CPU units, as the _monolithic template had it"

  validation {
    condition     = contains([256, 512, 1024, 2048, 4096, 8192, 16384], var.task_cpu)
    error_message = "task_cpu must be one of the Fargate CPU values: 256, 512, 1024, 2048, 4096, 8192 or 16384."
  }
}
variable "task_memory" {
  type        = number
  default     = 2048
  description = "Task memory in MiB, as the _monolithic template had it. Fargate accepts only certain values for each CPU value"

  validation {
    condition     = var.task_memory >= 512
    error_message = "task_memory must be at least 512 MiB."
  }
}
variable "task_role_arn" {
  type        = string
  description = "Role the containers run as. Shared between the two services, so it comes from the caller"

  validation {
    condition     = can(regex("^arn:aws[a-zA-Z-]*:iam::[0-9]{12}:role/", var.task_role_arn))
    error_message = "task_role_arn must be an IAM role ARN."
  }
}
variable "repository_arn" {
  type        = string
  description = "ECR repository the image is pulled from, which the execution role may pull from and nothing else"

  validation {
    condition     = can(regex("^arn:aws[a-zA-Z-]*:ecr:[a-z0-9-]+:[0-9]{12}:repository/.+$", var.repository_arn))
    error_message = "repository_arn must be an ECR repository ARN."
  }
}
variable "image" {
  type        = string
  description = "Image the container runs, <repository url>:<tag>"

  validation {
    condition     = can(regex("^[0-9]{12}\\.dkr\\.ecr\\.[a-z0-9-]+\\.amazonaws\\.com/.+:.+$", var.image))
    error_message = "image must be an ECR image reference with a tag, <account>.dkr.ecr.<region>.amazonaws.com/<repository>:<tag>."
  }
}
variable "container_port" {
  type        = number
  description = "Port the container listens on. The task definition, the PORT variable, the target group and both security groups take it from here (rules.md B-5)"

  validation {
    condition     = var.container_port > 0 && var.container_port <= 65535
    error_message = "container_port must be a valid TCP port."
  }
}
variable "environment" {
  type        = map(string)
  default     = {}
  description = "Environment variables for the container, in addition to PORT, which is always the container port"

  validation {
    condition     = !contains(keys(var.environment), "PORT")
    error_message = "environment must not set PORT - it is derived from container_port, so the two cannot disagree."
  }
}
variable "extra_security_group_ids" {
  type        = list(string)
  default     = []
  description = "Further security groups the tasks carry, such as a MemoryDB client group. Not iterated with for_each, so a list of other modules' outputs is safe here"

  validation {
    condition     = alltrue([for id in var.extra_security_group_ids : can(regex("^sg-[0-9a-f]+$", id))])
    error_message = "extra_security_group_ids must contain valid security group IDs."
  }
}
variable "log_group_name" {
  type        = string
  description = "Log group the container writes to"

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
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365], var.log_retention_in_days)
    error_message = "log_retention_in_days must be one of 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180 or 365."
  }
}
variable "desired_count" {
  type        = number
  default     = 2
  description = "Number of tasks, as the _monolithic template had it"

  validation {
    condition     = var.desired_count >= 0
    error_message = "desired_count must be zero or greater."
  }
}
variable "wait_for_steady_state" {
  type        = bool
  default     = true
  description = "Whether apply waits for the service to stabilise, which is what CloudFormation did for the _monolithic stack"
}
