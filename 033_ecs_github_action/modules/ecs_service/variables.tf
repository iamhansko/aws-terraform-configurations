variable "name" {
  type        = string
  default     = "ecs-cicd-service"
  description = "Name of the ECS service, as the _monolithic template named it. The CodeDeploy deployment group and the GitHub Actions workflow both name it"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,255}$", var.name))
    error_message = "name must be 1-255 characters of letters, digits, underscores or hyphens, which is what ECS accepts for a service name."
  }
}
variable "cluster_name" {
  type        = string
  description = "Name of the ECS cluster the service runs in, taken from the cluster module's output (rules.md B-5)"

  validation {
    condition     = length(var.cluster_name) > 0
    error_message = "cluster_name must not be empty."
  }
}
variable "vpc_id" {
  type        = string
  description = "VPC ID where the tasks' security group is created"

  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must be a valid VPC ID (e.g. vpc-0123456789abcdef0)."
  }
}
variable "subnet_ids" {
  type        = list(string)
  description = "Private subnets the awsvpc task ENIs are placed in, as the _monolithic template placed them"

  validation {
    condition     = length(var.subnet_ids) >= 1 && alltrue([for id in var.subnet_ids : can(regex("^subnet-[0-9a-f]+$", id))])
    error_message = "subnet_ids must contain at least one valid subnet ID (e.g. subnet-0123456789abcdef0)."
  }
}
variable "target_group_arn" {
  type        = string
  description = "ARN of the target group the service registers its tasks into. Must be the group the listener forwards to at creation, which is why the load balancer module hands back exactly that one (rules.md B-5)"

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:elasticloadbalancing:", var.target_group_arn))
    error_message = "target_group_arn must be an elasticloadbalancing target group ARN."
  }
}
variable "container_name" {
  type        = string
  default     = "python"
  description = "Name of the container, as the _monolithic template named it. The service's load_balancer block, the appspec's LoadBalancerInfo and the workflow's render-task-definition step all name it, so a change here has to reach all four"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9_-]{0,254}$", var.container_name))
    error_message = "container_name must be 1-255 characters of letters, digits, underscores or hyphens, starting with a letter or digit."
  }
}
variable "container_image" {
  type        = string
  description = "Full image reference including the tag, taken from the repository module so the push and the pull are one value (rules.md B-5). The _monolithic template passed the repository URL with no tag, which docker resolves to :latest"

  validation {
    condition     = can(regex("^[0-9]+\\.dkr\\.ecr\\.[a-z0-9-]+\\.amazonaws\\.com/.+:.+$", var.container_image))
    error_message = "container_image must be a tagged ECR image reference (<account>.dkr.ecr.<region>.amazonaws.com/<repository>:<tag>)."
  }
}
variable "container_port" {
  type        = number
  default     = 80
  description = "Port the container listens on. With awsvpc this is also the host port and the target group's port, so the caller passes the load balancer module's target_port here (rules.md B-5)"

  validation {
    condition     = var.container_port > 0 && var.container_port <= 65535
    error_message = "container_port must be a valid TCP port."
  }
}
variable "task_family" {
  type        = string
  default     = "ecs-task-def"
  description = "Task definition family, as the _monolithic template named it. The association that seeds the repository exports this family to taskdef.json and the workflow renders a new revision from that file, so the name is load-bearing outside Terraform"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,255}$", var.task_family))
    error_message = "task_family must be 1-255 characters of letters, digits, underscores or hyphens."
  }
}
variable "task_cpu" {
  type        = string
  default     = "512"
  description = "Task-level CPU units, as the _monolithic template had it"

  validation {
    condition     = can(regex("^[0-9]+$", var.task_cpu))
    error_message = "task_cpu must be a whole number of CPU units expressed as a string (e.g. \"512\")."
  }
}
variable "task_memory" {
  type        = string
  default     = "1024"
  description = "Task-level memory in MiB, as the _monolithic template had it. Two task sets run side by side during a blue/green cutover, so the container instance has to fit twice this"

  validation {
    condition     = can(regex("^[0-9]+$", var.task_memory))
    error_message = "task_memory must be a whole number of MiB expressed as a string (e.g. \"1024\")."
  }
}
variable "requires_compatibilities" {
  type        = list(string)
  default     = ["EC2", "FARGATE"]
  description = "Launch types the task definition is valid for, as the _monolithic template declared them. FARGATE is in the list because the workflow's Fargate branch rewrites the appspec to deploy the replacement task set onto Fargate, and a task definition without it is rejected at that point rather than here"

  validation {
    condition     = length(var.requires_compatibilities) > 0 && alltrue([for value in var.requires_compatibilities : contains(["EC2", "FARGATE", "EXTERNAL"], value)])
    error_message = "requires_compatibilities must be a non-empty subset of EC2, FARGATE and EXTERNAL."
  }
  validation {
    condition     = contains(var.requires_compatibilities, "EC2")
    error_message = "requires_compatibilities must include EC2. The service places with launch_type EC2 onto the capacity provider's container instances, and ECS rejects the service if the task definition is not compatible with that launch type."
  }
}
variable "cpu_architecture" {
  type        = string
  default     = "X86_64"
  description = "CPU architecture the task runs on, as the _monolithic template had it. It has to match the architecture the image was built for - the workbench builds on an x86_64 instance"

  validation {
    condition     = contains(["X86_64", "ARM64"], var.cpu_architecture)
    error_message = "cpu_architecture must be X86_64 or ARM64."
  }
}
variable "operating_system_family" {
  type        = string
  default     = "LINUX"
  description = "Operating system family the task runs on, as the _monolithic template had it"

  validation {
    condition     = can(regex("^[A-Z0-9_]+$", var.operating_system_family))
    error_message = "operating_system_family must be an upper-case ECS operating system family value (e.g. LINUX)."
  }
}
variable "launch_type" {
  type        = string
  default     = "EC2"
  description = "How the service places tasks, as the _monolithic template had it. EC2 rather than a capacity provider strategy, so the service consumes the container instances directly; the replacement task set a CodeDeploy deployment creates takes its strategy from the appspec instead"

  validation {
    condition     = contains(["EC2", "FARGATE", "EXTERNAL"], var.launch_type)
    error_message = "launch_type must be EC2, FARGATE or EXTERNAL."
  }
}
variable "desired_count" {
  type        = number
  default     = 1
  description = "Number of tasks the service keeps running, as the _monolithic template had it"

  validation {
    condition     = var.desired_count >= 0
    error_message = "desired_count must be zero or greater."
  }
}
variable "wait_for_steady_state" {
  type        = bool
  default     = false
  description = "Whether apply blocks until the service reaches a steady state. False here, unlike most services in this repository: with a CODE_DEPLOY controller the first task set is created by ECS but subsequent rollouts are CodeDeploy's, and a service whose image is wrong would hold the apply open for the full timeout before failing on something the workbench's association already reports"
}
variable "health_check_path" {
  type        = string
  default     = "/health"
  description = "Path the container health check requests on localhost. The same path the target groups check, taken from the load balancer module (rules.md B-5)"

  validation {
    condition     = can(regex("^/", var.health_check_path))
    error_message = "health_check_path must start with '/'."
  }
}
variable "health_check_interval" {
  type        = number
  default     = 30
  description = "Seconds between container health checks, as the _monolithic template had it"

  validation {
    condition     = var.health_check_interval >= 5 && var.health_check_interval <= 300
    error_message = "health_check_interval must be between 5 and 300 seconds."
  }
}
variable "health_check_retries" {
  type        = number
  default     = 5
  description = "Failed container health checks before the container is considered unhealthy, as the _monolithic template had it"

  validation {
    condition     = var.health_check_retries >= 1 && var.health_check_retries <= 10
    error_message = "health_check_retries must be between 1 and 10."
  }
}
variable "health_check_start_period" {
  type        = number
  default     = 5
  description = "Grace period in seconds before failed container health checks count, as the _monolithic template had it"

  validation {
    condition     = var.health_check_start_period >= 0 && var.health_check_start_period <= 300
    error_message = "health_check_start_period must be between 0 and 300 seconds."
  }
}
variable "health_check_timeout" {
  type        = number
  default     = 5
  description = "Seconds a container health check may take, as the _monolithic template had it"

  validation {
    condition     = var.health_check_timeout >= 2 && var.health_check_timeout <= 60
    error_message = "health_check_timeout must be between 2 and 60 seconds."
  }
  validation {
    condition     = var.health_check_timeout < var.health_check_interval
    error_message = "health_check_timeout must be shorter than health_check_interval, otherwise a check can still be running when the next one is due."
  }
}
variable "security_group_name" {
  type        = string
  default     = "ecs-service-sg"
  description = "Name of the tasks' security group, as the _monolithic template named it"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.security_group_name)) && !startswith(var.security_group_name, "sg-")
    error_message = "security_group_name must be 1-255 characters from the set AWS accepts for a security group name (a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*, no apostrophe) and must not start with \"sg-\", which EC2 reserves for security group IDs."
  }
}
variable "security_group_description" {
  type        = string
  default     = "Security group for the awsvpc task ENIs behind the blue/green ALB"
  description = "Description attached to the tasks' security group"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.security_group_description))
    error_message = "security_group_description must be 1-255 characters from the set AWS accepts for a security group description: a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*. An apostrophe is NOT allowed - EC2 rejects CreateSecurityGroup with InvalidParameterValue, and changing this value replaces the group (rules.md F-1)."
  }
}
variable "container_port_ingress_source_security_groups" {
  type        = map(string)
  default     = {}
  description = "Security group IDs allowed inbound on container_port, keyed by a caller-chosen label. A map rather than a list because these IDs are another module's output and unknown until apply, and for_each needs statically known keys (rules.md B-8)"

  validation {
    condition     = alltrue([for label in keys(var.container_port_ingress_source_security_groups) : can(regex("^[a-zA-Z0-9._-]+$", label))])
    error_message = "container_port_ingress_source_security_groups keys appear in the rule descriptions and in the resource addresses, so each must be a non-empty string of letters, digits, dots, underscores or hyphens."
  }
  validation {
    condition     = alltrue([for id in values(var.container_port_ingress_source_security_groups) : can(regex("^sg-[0-9a-f]+$", id))])
    error_message = "container_port_ingress_source_security_groups must contain valid security group IDs (e.g. sg-0123456789abcdef0)."
  }
}
variable "all_traffic_ingress_source_security_groups" {
  type        = map(string)
  default     = {}
  description = "Security group IDs allowed all inbound traffic, keyed by a caller-chosen label. Separate from the container-port map because the _monolithic template's rules were not all on one protocol (rules.md B-8)"

  validation {
    condition     = alltrue([for label in keys(var.all_traffic_ingress_source_security_groups) : can(regex("^[a-zA-Z0-9._-]+$", label))])
    error_message = "all_traffic_ingress_source_security_groups keys appear in the rule descriptions and in the resource addresses, so each must be a non-empty string of letters, digits, dots, underscores or hyphens."
  }
  validation {
    condition     = alltrue([for id in values(var.all_traffic_ingress_source_security_groups) : can(regex("^sg-[0-9a-f]+$", id))])
    error_message = "all_traffic_ingress_source_security_groups must contain valid security group IDs (e.g. sg-0123456789abcdef0)."
  }
}
variable "task_execution_policy_arns" {
  type        = list(string)
  default     = ["arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"]
  description = "IAM managed policy ARNs attached to the task execution role - what the ECS agent uses to pull the image. The _monolithic template also attached SecretsManagerReadWrite here, which is dropped: nothing in this project reads a secret, and that policy carries full secretsmanager access plus cloudformation, lambda, rds, redshift and tagging permissions on a role every task assumes (rules.md A-5). Add it back through this variable if a task is given a secret to read"

  validation {
    condition     = alltrue([for arn in var.task_execution_policy_arns : can(regex("^arn:aws:iam::", arn))])
    error_message = "task_execution_policy_arns must contain valid IAM policy ARNs."
  }
  validation {
    condition     = contains(var.task_execution_policy_arns, "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy")
    error_message = "task_execution_policy_arns must include AmazonECSTaskExecutionRolePolicy. Without it the agent cannot fetch an ECR authorization token, and the task stops with CannotPullContainerError naming the role rather than the missing policy."
  }
}
variable "task_policy_arns" {
  type        = list(string)
  default     = []
  description = "IAM managed policy ARNs attached to the task role - what the container itself runs as. Empty as the _monolithic template left it: the seeded Flask application makes no AWS calls"

  validation {
    condition     = alltrue([for arn in var.task_policy_arns : can(regex("^arn:aws:iam::", arn))])
    error_message = "task_policy_arns must contain valid IAM policy ARNs."
  }
}
