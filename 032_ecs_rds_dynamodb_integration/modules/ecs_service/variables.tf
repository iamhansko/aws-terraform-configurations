variable "service_name" {
  type        = string
  description = "Name of the service. No default: the caller derives one per application, as the _monolithic template named them user-service, product-service and stress-service"
  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9_-]{0,254}$", var.service_name))
    error_message = "service_name must be 1-255 characters of letters, digits, underscores and hyphens, starting with a letter or digit."
  }
}
variable "task_family" {
  type        = string
  description = "Task definition family. No default: one per application, which is the correction to the template giving all three \"user-taskdef\" - see main.tf"
  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9_-]{0,254}$", var.task_family))
    error_message = "task_family must be 1-255 characters of letters, digits, underscores and hyphens, starting with a letter or digit."
  }
}
variable "cluster_name" {
  type        = string
  description = "Cluster the service runs in"
  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9_-]{0,254}$", var.cluster_name))
    error_message = "cluster_name must be 1-255 characters of letters, digits, underscores and hyphens, starting with a letter or digit."
  }
}
variable "subnet_ids" {
  type        = list(string)
  description = "Subnets the task ENIs are placed in. Private, so the tasks reach DynamoDB, Secrets Manager and CloudWatch Logs through the NAT gateways - an awsvpc task ENI on an EC2 instance never gets a public address, so a public subnet would leave them with no route out at all"
  validation {
    condition     = length(var.subnet_ids) > 0 && alltrue([for id in var.subnet_ids : can(regex("^subnet-[0-9a-f]+$", id))])
    error_message = "subnet_ids must contain at least one valid subnet ID."
  }
}
variable "security_group_ids" {
  type        = list(string)
  description = "Security groups attached to each task ENI. A list rather than a map, because this value is used as an argument and never as a for_each key - the map shape rules.md B-8 asks for is only needed where unknown values would have to become resource addresses"
  validation {
    condition     = length(var.security_group_ids) > 0 && length(var.security_group_ids) <= 5
    error_message = "security_group_ids must contain between one and five groups, which is the limit awsVpcConfiguration accepts."
  }
}
variable "image_uri" {
  type        = string
  description = "Image the task pulls, including the tag. Taken from the repository module by the caller so the push and the pull name one value (rules.md B-5)"
  validation {
    condition     = length(var.image_uri) > 0
    error_message = "image_uri must not be empty."
  }
}
variable "container_name" {
  type        = string
  default     = "golang"
  description = "Name of the container inside the task, as the template had it for all three. It is what appears in a log stream name and what ECS Exec and describe-tasks identify the container by"
  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9_-]{0,254}$", var.container_name))
    error_message = "container_name must be 1-255 characters of letters, digits, underscores and hyphens, starting with a letter or digit."
  }
}
variable "container_port" {
  type        = number
  default     = 8080
  description = "Port the container listens on, as every one of the three applications does (router.Run(\":8080\")). The same value becomes the host port, the health check's target and the security group rule the caller opens (rules.md B-5)"
  validation {
    condition     = var.container_port > 0 && var.container_port <= 65535
    error_message = "container_port must be a valid TCP port."
  }
}
variable "port_mapping_name" {
  type        = string
  default     = "http"
  description = "Name of the port mapping, as the template had it. Only meaningful to Service Connect, which nothing here uses, but a named mapping costs nothing and ECS requires the name when a mapping is named at all"
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,63}$", var.port_mapping_name))
    error_message = "port_mapping_name must be 1-64 characters of lowercase letters, digits and hyphens, starting with a letter or digit."
  }
}
variable "task_cpu" {
  type        = string
  default     = "512"
  description = "CPU units reserved for the task, as the template had it. A string because the API takes one. 512 is half a vCPU, so two tasks fit a t3.medium's 2048 units - which matches the two-task-per-instance ceiling the ENI limit imposes anyway"
  validation {
    condition     = can(regex("^[0-9]+$", var.task_cpu))
    error_message = "task_cpu must be a whole number of CPU units expressed as a string (e.g. \"512\")."
  }
}
variable "task_memory" {
  type        = string
  default     = "1024"
  description = "Memory in MiB reserved for the task, as the template had it. A hard reservation on the EC2 launch type: the instance must have this much unallocated or the task is not placed, and the service reports that as no instance meeting its requirements"
  validation {
    condition     = can(regex("^[0-9]+$", var.task_memory))
    error_message = "task_memory must be a whole number of MiB expressed as a string (e.g. \"1024\")."
  }
}
variable "network_mode" {
  type        = string
  default     = "awsvpc"
  description = "Task network mode, as the template had it. awsvpc is what gives each task its own ENI and security group; this module's network_configuration block depends on it, and ECS rejects that block for any other mode"
  validation {
    condition     = var.network_mode == "awsvpc"
    error_message = "network_mode must be awsvpc. This module always declares a network_configuration block, which ECS only accepts for awsvpc - bridge or host would need that block removed and the container instance security group opened instead."
  }
}
variable "requires_compatibilities" {
  type        = list(string)
  default     = ["EC2"]
  description = "Launch types the task definition declares compatibility with, as the template had it. EC2 only, which is what makes the Fargate providers on the cluster unusable by these tasks"
  validation {
    condition     = length(var.requires_compatibilities) > 0 && alltrue([for value in var.requires_compatibilities : contains(["EC2", "FARGATE", "EXTERNAL"], value)])
    error_message = "requires_compatibilities must contain at least one of EC2, FARGATE or EXTERNAL."
  }
}
variable "cpu_architecture" {
  type        = string
  default     = "X86_64"
  description = "CPU architecture the task requires, as the template had it. It has to match what the image was built for: the workbench is an x86_64 instance, so this and the images agree - an arm64 image here stops the task with an \"image manifest does not contain descriptor matching platform\" error"
  validation {
    condition     = contains(["X86_64", "ARM64"], var.cpu_architecture)
    error_message = "cpu_architecture must be X86_64 or ARM64."
  }
}
variable "operating_system_family" {
  type        = string
  default     = "LINUX"
  description = "Operating system family the task requires, as the template had it"
  validation {
    condition     = can(regex("^(LINUX|WINDOWS_SERVER_[0-9A-Z_]+)$", var.operating_system_family))
    error_message = "operating_system_family must be LINUX or a WINDOWS_SERVER_* value."
  }
}
variable "environment" {
  type        = map(string)
  default     = {}
  description = "Plaintext environment variables for the container. A map, rendered as a sorted list so the task definition does not churn on ordering. Anything secret belongs in the secrets variable instead - an environment entry is stored in the task definition in the clear and stays in every revision (see main.tf)"
  validation {
    condition     = alltrue([for key in keys(var.environment) : can(regex("^[A-Za-z_][A-Za-z0-9_]*$", key))])
    error_message = "environment keys must be valid shell environment variable names."
  }
  validation {
    condition     = !anytrue([for key in keys(var.environment) : can(regex("(?i)password|secret|token|credential", key))])
    error_message = "environment must not contain a key that looks like a credential (password, secret, token, credential). Those belong in the secrets variable: the _monolithic template passed MYSQL_PASSWORD here, which puts the password in plaintext into every task definition revision for anyone who can call ecs:DescribeTaskDefinition."
  }
}
variable "secrets" {
  type        = map(string)
  default     = {}
  description = "Environment variables resolved from Secrets Manager or Parameter Store before the container starts, mapped to their valueFrom references. A Secrets Manager reference may select one key out of a JSON document with a \":<key>::\" suffix, which is how MYSQL_PASSWORD is injected without the rest of the credential document reaching the container"
  validation {
    condition     = alltrue([for key in keys(var.secrets) : can(regex("^[A-Za-z_][A-Za-z0-9_]*$", key))])
    error_message = "secrets keys must be valid shell environment variable names."
  }
  validation {
    condition     = alltrue([for value in values(var.secrets) : can(regex("^arn:aws[a-z-]*:(secretsmanager|ssm):", value))])
    error_message = "secrets values must be Secrets Manager secret ARNs or SSM parameter ARNs. The task execution role additionally needs permission to read each one, or the task stops before the container starts with a ResourceInitializationError."
  }
}
variable "task_role_arn" {
  type        = string
  description = "Role assumed by the process inside the container"
  validation {
    condition     = can(regex("^arn:aws[a-z-]*:iam::", var.task_role_arn))
    error_message = "task_role_arn must be an IAM role ARN."
  }
}
variable "execution_role_arn" {
  type        = string
  description = "Role assumed by the ECS agent before the container starts, for the ECR pull, the secret injection and the log stream"
  validation {
    condition     = can(regex("^arn:aws[a-z-]*:iam::", var.execution_role_arn))
    error_message = "execution_role_arn must be an IAM role ARN."
  }
}
variable "log_group_name" {
  type        = string
  description = "CloudWatch log group the container writes to. No default: the caller derives one per application, so three services do not interleave into one group"
  validation {
    condition     = can(regex("^[a-zA-Z0-9_/.#-]{1,512}$", var.log_group_name))
    error_message = "log_group_name must be 1-512 characters of letters, digits, underscores, slashes, dots, hashes and hyphens."
  }
}
variable "log_retention_in_days" {
  type        = number
  default     = 7
  description = "Days of container output kept. The _monolithic template had no log group at all, so there was nothing to retain; seven days is enough to diagnose a demo and short enough not to accumulate"
  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_in_days)
    error_message = "log_retention_in_days must be one of the values CloudWatch Logs accepts (1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653)."
  }
}
variable "log_stream_prefix" {
  type        = string
  default     = "ecs"
  description = "Prefix for the log stream name, which the driver completes as <prefix>/<container>/<task-id>. Without a prefix the driver uses the container id alone, which is not something a person can correlate with a task"
  validation {
    condition     = can(regex("^[a-zA-Z0-9_.-]{1,128}$", var.log_stream_prefix))
    error_message = "log_stream_prefix must be 1-128 characters of letters, digits, underscores, dots and hyphens - a slash would make the stream name ambiguous."
  }
}
variable "desired_count" {
  type        = number
  default     = 1
  description = "Tasks the service keeps running, as the template had it for all three"
  validation {
    condition     = var.desired_count >= 0
    error_message = "desired_count must be zero or more."
  }
}
variable "capacity_provider_name" {
  type        = string
  description = "Capacity provider the service places tasks through. The provider's name, not its ARN - see main.tf"
  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9_-]{0,254}$", var.capacity_provider_name))
    error_message = "capacity_provider_name must be 1-255 characters of letters, digits, underscores and hyphens, starting with a letter or digit. An ARN here is accepted by the API and then never matches what ECS reads back."
  }
}
variable "capacity_provider_base" {
  type        = number
  default     = 0
  description = "Tasks placed on this provider before the weight applies. Zero, which is the only sensible value with one provider in the strategy"
  validation {
    condition     = var.capacity_provider_base >= 0 && var.capacity_provider_base <= 100000
    error_message = "capacity_provider_base must be between 0 and 100000."
  }
}
variable "capacity_provider_weight" {
  type        = number
  default     = 100
  description = "Relative share of tasks this provider takes. Arbitrary above zero with one provider in the strategy"
  validation {
    condition     = var.capacity_provider_weight >= 1 && var.capacity_provider_weight <= 1000
    error_message = "capacity_provider_weight must be between 1 and 1000. Zero would mean the strategy places nothing on the only provider it names."
  }
}
variable "health_check_path" {
  type        = string
  default     = "/healthcheck"
  description = "Path the container health check requests, which is the route all three applications expose. A container-level health check rather than a load balancer one, as the template had it: there is no load balancer here, so this is the only thing that notices a process that is up but not serving"
  validation {
    condition     = can(regex("^/", var.health_check_path))
    error_message = "health_check_path must start with '/'."
  }
}
variable "health_check_interval" {
  type        = number
  default     = 30
  description = "Seconds between health checks, as the template had it"
  validation {
    condition     = var.health_check_interval >= 5 && var.health_check_interval <= 300
    error_message = "health_check_interval must be between 5 and 300 seconds."
  }
}
variable "health_check_retries" {
  type        = number
  default     = 5
  description = "Consecutive failures before the container is considered unhealthy, as the template had it"
  validation {
    condition     = var.health_check_retries >= 1 && var.health_check_retries <= 10
    error_message = "health_check_retries must be between 1 and 10."
  }
}
variable "health_check_timeout" {
  type        = number
  default     = 5
  description = "Seconds a single health check may take, as the template had it"
  validation {
    condition     = var.health_check_timeout >= 2 && var.health_check_timeout <= 60
    error_message = "health_check_timeout must be between 2 and 60 seconds."
  }
}
variable "health_check_start_period" {
  type        = number
  default     = 30
  description = "Grace period before failed checks start counting, which the template did not set. Without it the user application's container is checked from the first second, and its /healthcheck answers before the database connection is established - so the grace period is not needed to pass, it is there so a slow start is not counted as a failure"
  validation {
    condition     = var.health_check_start_period >= 0 && var.health_check_start_period <= 300
    error_message = "health_check_start_period must be between 0 and 300 seconds."
  }
}
variable "enable_execute_command" {
  type        = bool
  default     = true
  description = "Whether ECS Exec can open a shell in a running task. On, which the template did not have. It is the only way to see inside one of these containers - there is no load balancer and the tasks have no public address - and it needs no extra IAM here, because the task role would need ssmmessages permissions only on Fargate; on the EC2 launch type the agent uses the container instance role, which carries AmazonSSMManagedInstanceCore"
}
variable "wait_for_steady_state" {
  type        = bool
  default     = false
  description = "Whether apply blocks until the service reports a steady state. False, so an apply is not held for the several minutes a first deployment takes - the trade is that apply succeeding does not mean the tasks are running, and the service event commands in the outputs are how to tell. True is the right setting for a pipeline"
}
