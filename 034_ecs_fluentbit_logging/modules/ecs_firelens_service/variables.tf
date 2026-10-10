variable "cluster_name" {
  type        = string
  description = "Name of the ECS cluster the service runs in. Taken as a name rather than looked up, so this module does not have to know how the cluster was created (rules.md B-6)"
  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9_-]{0,254}$", var.cluster_name))
    error_message = "cluster_name must be 1-255 characters of letters, digits, underscores and hyphens, starting with a letter or digit."
  }
}
variable "service_name" {
  type        = string
  default     = "logging-svc"
  description = "Name of the service, as the _monolithic template named it"
  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9_-]{0,254}$", var.service_name))
    error_message = "service_name must be 1-255 characters of letters, digits, underscores and hyphens, starting with a letter or digit."
  }
}
variable "task_family" {
  type        = string
  default     = "logging-ecs-td"
  description = "Task definition family, as the _monolithic template named it"
  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9_-]{0,254}$", var.task_family))
    error_message = "task_family must be 1-255 characters of letters, digits, underscores and hyphens, starting with a letter or digit."
  }
}
variable "capacity_provider_name" {
  type        = string
  description = "Name of the capacity provider the service places tasks through. The provider's name rather than its ARN - ECS reads this field back as a name, so an ARN leaves a difference between configuration and state that never settles"
  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9_-]{0,254}$", var.capacity_provider_name))
    error_message = "capacity_provider_name must be a capacity provider name, not an ARN."
  }
}
variable "capacity_provider_base" {
  type        = number
  default     = 0
  description = "Tasks placed on this provider before the weight is applied"
  validation {
    condition     = var.capacity_provider_base >= 0
    error_message = "capacity_provider_base must be zero or greater."
  }
}
variable "capacity_provider_weight" {
  type        = number
  default     = 100
  description = "Relative share of tasks sent to this provider. There is only one, so any positive value means all of them"
  validation {
    condition     = var.capacity_provider_weight >= 0
    error_message = "capacity_provider_weight must be zero or greater."
  }
}
variable "desired_count" {
  type        = number
  default     = 2
  description = "Copies of the task the service keeps running, as the _monolithic template had it. Two is useful here rather than arbitrary: each task has its own Fluent Bit sidecar, so the delivered records carry two different ecs_task_arn values and two different stream names, which is what shows that the metadata FireLens adds is per-task. Both fit on one t3.medium container instance"
  validation {
    condition     = var.desired_count >= 0
    error_message = "desired_count must be zero or greater."
  }
}
variable "task_cpu" {
  type        = string
  default     = "512"
  description = "CPU units reserved for the whole task, shared by both containers, as the _monolithic template had it"
  validation {
    condition     = can(regex("^[0-9]+$", var.task_cpu))
    error_message = "task_cpu must be a whole number of CPU units expressed as a string (e.g. \"512\")."
  }
}
variable "task_memory" {
  type        = string
  default     = "1024"
  description = "Memory in MiB reserved for the whole task, shared by both containers, as the _monolithic template had it"
  validation {
    condition     = can(regex("^[0-9]+$", var.task_memory))
    error_message = "task_memory must be a whole number of MiB expressed as a string (e.g. \"1024\")."
  }
}
variable "network_mode" {
  type        = string
  default     = "bridge"
  description = <<-DESC
    Docker network mode for the task, as the _monolithic template had it.
    bridge is what makes the container instance's security group the tasks' security group, which is why
    that group's egress rule is what Fluent Bit's deliveries depend on. It is also what makes the
    container dependency in main.tf necessary and what makes publishing port 24224 a mistake.
    awsvpc would give each task its own interface and its own security group, and would then need a
    network_configuration block on the service - which is the block the _monolithic template's unused
    ecs_service_security_group was presumably written for.
  DESC
  validation {
    condition     = contains(["bridge", "host", "awsvpc", "none"], var.network_mode)
    error_message = "network_mode must be bridge, host, awsvpc or none."
  }
  validation {
    # Cross-key rather than cross-variable: awsvpc needs a network_configuration block that this module
    # does not declare, so selecting it here produces a service with no subnets and a task that cannot be
    # placed, reported only as a service event (rules.md B-1).
    condition     = var.network_mode != "awsvpc"
    error_message = "network_mode cannot be awsvpc in this module, because the service declares no network_configuration block for the subnets and security groups that mode requires. Use bridge, which is what the _monolithic template used, or add that block and a subnet list first."
  }
}
variable "cpu_architecture" {
  type        = string
  default     = "X86_64"
  description = "CPU architecture of the images, as the _monolithic template declared it. It has to match what the build produced and what the container instances are: a mismatch surfaces as a stopped task whose reason names the image manifest, not the architecture"
  validation {
    condition     = contains(["X86_64", "ARM64"], var.cpu_architecture)
    error_message = "cpu_architecture must be X86_64 or ARM64."
  }
}
variable "application_container_name" {
  type        = string
  default     = "app-logger"
  description = "Name of the application container, as the _monolithic template named it. FireLens builds the record tag from it, so it also appears in every delivered log stream name"
  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9_-]{0,254}$", var.application_container_name))
    error_message = "application_container_name must be 1-255 characters of letters, digits, underscores and hyphens, starting with a letter or digit."
  }
}
variable "application_image_uri" {
  type        = string
  description = "Image the application container runs. Built and pushed by an SSM association in the root, which is also what orders this module after it"
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]*(:[0-9]+)?/[^:]+:[^:]+$", var.application_image_uri))
    error_message = "application_image_uri must be a registry-qualified image reference carrying an explicit tag (e.g. 123456789012.dkr.ecr.ap-northeast-2.amazonaws.com/logging-ecr:v1.0.0)."
  }
}
variable "log_router_container_name" {
  type        = string
  default     = "log-router"
  description = "Name of the Fluent Bit sidecar, as the _monolithic template named it. The application container's dependency names it, so the two have to agree - and a dependency on a container name that does not exist is rejected when the task definition is registered"
  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9_-]{0,254}$", var.log_router_container_name))
    error_message = "log_router_container_name must be 1-255 characters of letters, digits, underscores and hyphens, starting with a letter or digit."
  }
}
variable "log_router_image_uri" {
  type        = string
  description = "Image the log router runs. In this project that is AWS's published aws-for-fluent-bit image, pulled and re-pushed into a private repository by the root's build association"
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]*(:[0-9]+)?/[^:]+:[^:]+$", var.log_router_image_uri))
    error_message = "log_router_image_uri must be a registry-qualified image reference carrying an explicit tag (e.g. 123456789012.dkr.ecr.ap-northeast-2.amazonaws.com/logging-fluentbit:v1.0.0)."
  }
}
variable "firelens_type" {
  type        = string
  default     = "fluentbit"
  description = "Which log router the image contains, as the _monolithic template declared it. It selects the path the agent mounts the generated configuration at - /fluent-bit/etc/fluent-bit.conf for fluentbit, /fluentd/etc/fluent.conf for fluentd - so declaring the wrong one leaves the router running its image's own default configuration and delivering nothing"
  validation {
    condition     = contains(["fluentbit", "fluentd"], var.firelens_type)
    error_message = "firelens_type must be fluentbit or fluentd."
  }
}
variable "application_firelens_options" {
  type        = map(string)
  description = "Options for the application container's awsfirelens log configuration. Supplied whole by the log destination module, so the group the task writes to, the group the IAM policy grants and the group the README's verification command reads are one value (rules.md B-5)"
  validation {
    condition     = contains(keys(var.application_firelens_options), "Name")
    error_message = "application_firelens_options must contain a Name key, which selects the Fluent Bit output plugin. Without it the agent generates a configuration with no [OUTPUT] section at all, the task runs healthy, and nothing is ever delivered."
  }
  validation {
    condition     = lookup(var.application_firelens_options, "Name", "") != "cloudwatch_logs" || contains(keys(var.application_firelens_options), "log_group_name")
    error_message = "application_firelens_options must contain log_group_name when Name is cloudwatch_logs. The plugin has no default group, so it reports the missing option in the log router's own log and delivers nothing."
  }
}
variable "log_router_awslogs_options" {
  type        = map(string)
  description = "Options for the log router container's own awslogs log configuration, supplied whole by the log destination module. This is the channel that reports a broken pipeline, so it deliberately does not go through the router itself"
  validation {
    condition     = contains(keys(var.log_router_awslogs_options), "awslogs-group") && contains(keys(var.log_router_awslogs_options), "awslogs-region")
    error_message = "log_router_awslogs_options must contain awslogs-group and awslogs-region. The awslogs driver fails the container start without them, which stops the whole task because the router is essential."
  }
  validation {
    condition     = lookup(var.log_router_awslogs_options, "awslogs-create-group", "false") == "false"
    error_message = "awslogs-create-group must be absent or \"false\". Neither of the two roles the driver can authenticate as carries logs:CreateLogGroup - AmazonECSTaskExecutionRolePolicy does not, and neither does AmazonEC2ContainerServiceforEC2Role - so a true here fails the container start with an access denied from CloudWatch Logs. Declare the log group instead, which is what the firelens_log_destination module does."
  }
}
variable "log_router_environment" {
  type        = map(string)
  default     = { FLB_LOG_LEVEL = "info" }
  description = <<-DESC
    Environment variables for the log router container.
    The _monolithic template set FLB_LOG_LEVEL=error. This is info instead, and the change is the point
    of the variable: at error level a working pipeline writes nothing at all to the router's log group,
    so the one channel that could confirm the pipeline is working looks exactly like a broken one. At info
    the router logs its version, the output plugin it loaded and the destination it resolved, which is
    what turns an empty application log group into a diagnosable state.
    Set it back to error for anything long-running, where the volume matters more than the confirmation.
  DESC
  validation {
    condition     = alltrue([for name in keys(var.log_router_environment) : can(regex("^[A-Za-z_][A-Za-z0-9_]*$", name))])
    error_message = "log_router_environment keys must be valid environment variable names."
  }
  validation {
    condition     = contains(["trace", "debug", "info", "warn", "warning", "error", "off"], lower(lookup(var.log_router_environment, "FLB_LOG_LEVEL", "info")))
    error_message = "FLB_LOG_LEVEL must be one of trace, debug, info, warn, warning, error or off. Fluent Bit exits on an unrecognised level, which stops the essential log router container and therefore the whole task."
  }
}
variable "log_router_memory_reservation" {
  type        = number
  default     = 50
  description = "Soft memory limit in MiB for the log router, which the _monolithic template did not set. 50 is the figure AWS's FireLens guidance uses for a sidecar at this throughput. A reservation rather than a hard limit, so a burst of records does not have the router killed mid-delivery"
  validation {
    condition     = var.log_router_memory_reservation >= 4
    error_message = "log_router_memory_reservation must be at least 4 MiB, which is the minimum Docker accepts."
  }
}
variable "task_role_policy_arns" {
  type        = map(string)
  default     = {}
  description = <<-DESC
    Managed or customer policy ARNs attached to the task role, keyed by a caller-chosen label.
    The task role is the one Fluent Bit itself assumes, so this is where the log delivery permission
    belongs. The _monolithic template attached CloudWatchFullAccessV2 here, which grants logs:*,
    cloudwatch:*, xray:*, rum:*, synthetics:* and application-signals:* on every resource in the account;
    the root attaches a policy scoped to one log group instead (rules.md A-5).
    A map rather than a list because these ARNs come from another module and are unknown at plan time,
    while a for_each key has to be known then (rules.md B-8).
  DESC
  validation {
    condition     = alltrue([for label in keys(var.task_role_policy_arns) : can(regex("^[a-zA-Z0-9._-]+$", label))])
    error_message = "task_role_policy_arns keys are labels used in the resource addresses, so each must be a non-empty string of letters, digits, dots, underscores or hyphens."
  }
}
variable "task_execution_role_policy_arns" {
  type        = list(string)
  default     = ["arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"]
  description = <<-DESC
    Managed policy ARNs attached to the task execution role, which is the role the ECS agent uses on the
    task's behalf before any container starts.
    AmazonECSTaskExecutionRolePolicy and nothing else. It carries the ECR pull actions for both images
    and the logs:CreateLogStream and logs:PutLogEvents the awslogs driver needs for the log router's own
    stream. The _monolithic template also attached CloudWatchFullAccessV2 here, and the only thing in
    that policy this role actually needed was logs:CreateLogGroup for awslogs-create-group - which is not
    needed at all once the group is declared in Terraform.
    A list rather than a map because these are literal ARNs in configuration, known at plan time
    (rules.md B-7).
  DESC
  validation {
    condition     = length(var.task_execution_role_policy_arns) > 0 && alltrue([for arn in var.task_execution_role_policy_arns : can(regex("^arn:aws[a-z-]*:iam::", arn))])
    error_message = "task_execution_role_policy_arns must be a non-empty list of IAM policy ARNs. Without the ECR permissions it carries, neither image can be pulled and the service reports CannotPullContainerError."
  }
}
variable "wait_for_steady_state" {
  type        = bool
  default     = false
  description = "Whether apply blocks until the service reports a steady state. False, deliberately: a service that cannot converge is exactly when the root's outputs and the README written onto the workbench are worth having, and with this true the apply fails before the association that writes that README has run. Turn it on when the apply itself should be the thing that fails"
}
