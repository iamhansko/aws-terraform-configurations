variable "region" {
  type        = string
  description = "Region the awslogs driver is told to write to. Passed in rather than read from a data source, so this module contains no data source and nothing in it is deferred to apply when the caller orders it with depends_on (rules.md D-6)"

  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]$", var.region))
    error_message = "region must be an AWS region code such as ap-northeast-2."
  }
}
variable "vpc_id" {
  type        = string
  description = "VPC the task security group is created in"

  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must be a valid VPC ID (e.g. vpc-0123456789abcdef0)."
  }
}
variable "subnet_ids" {
  type        = list(string)
  description = "Subnets the task network interfaces are placed in. Private ones, so the tasks reach ECR and CloudWatch Logs through the NAT gateways"

  validation {
    condition     = length(var.subnet_ids) > 0
    error_message = "subnet_ids must not be empty."
  }
  validation {
    condition     = alltrue([for id in var.subnet_ids : can(regex("^subnet-[0-9a-f]+$", id))])
    error_message = "subnet_ids must contain valid subnet IDs (e.g. subnet-0123456789abcdef0)."
  }
}
variable "cluster_name" {
  type        = string
  description = "Cluster the service runs in. Taken by the caller from the cluster module's output rather than written as a literal, which is what creates the dependency edge the _monolithic template did not have"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,255}$", var.cluster_name))
    error_message = "cluster_name must be 1-255 characters of letters, digits, underscores and hyphens."
  }
}
variable "service_name" {
  type        = string
  description = "Name of the service. The CodeDeploy deployment group names it, and so does every status command"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,255}$", var.service_name))
    error_message = "service_name must be 1-255 characters of letters, digits, underscores and hyphens."
  }
}
variable "task_family" {
  type        = string
  description = "Task definition family. The CodeBuild buildspec registers new revisions into this same family, so the value is shared with that module (rules.md B-5)"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,255}$", var.task_family))
    error_message = "task_family must be 1-255 characters of letters, digits, underscores and hyphens."
  }
}
variable "container_name" {
  type        = string
  description = "Name of the single container. CodeDeploy's appspec names it under LoadBalancerInfo and the service's load_balancer block names it, so a mismatch stops a deployment rather than the apply"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9_-]{0,254}$", var.container_name))
    error_message = "container_name must be 1-255 characters of letters, digits, underscores and hyphens, starting with a letter or digit."
  }
}
variable "container_port" {
  type        = number
  default     = 80
  description = "Port the container listens on, which with awsvpc is also the host port and the target group's registration port. One value for all three (rules.md B-5)"

  validation {
    condition     = var.container_port >= 1 && var.container_port <= 65535
    error_message = "container_port must be between 1 and 65535."
  }
}
variable "image_uri" {
  type        = string
  description = "Image this revision pulls. The seed image the bastion pushed, taken from the repository module so the push and the pull are one value (rules.md B-5). Later revisions are registered by CodeBuild and name a timestamped tag instead"

  validation {
    condition     = can(regex("^[0-9]+\\.dkr\\.ecr\\.[a-z0-9-]+\\.amazonaws\\.com/[a-z0-9._/-]+:[a-zA-Z0-9._-]+$", var.image_uri))
    error_message = "image_uri must be a fully qualified ECR image reference including a tag, such as 123456789012.dkr.ecr.ap-northeast-2.amazonaws.com/stem-ecr:prototype. An untagged reference is accepted by ECS and resolves to :latest, which this project never pushes."
  }
}
variable "health_check_path" {
  type        = string
  default     = "/health"
  description = "Path the container's own health check requests, taken by the caller from the load balancer module so the container check and the target group check hit the same route (rules.md B-5)"

  validation {
    condition     = startswith(var.health_check_path, "/")
    error_message = "health_check_path must start with a slash."
  }
}
variable "task_cpu" {
  type        = number
  default     = 256
  description = "CPU units reserved for the task, as the _monolithic template had it. Also the value the buildspec's generated task definition uses"

  validation {
    condition     = var.task_cpu >= 128 && var.task_cpu <= 10240
    error_message = "task_cpu must be between 128 and 10240 CPU units."
  }
}
variable "task_memory" {
  type        = number
  default     = 512
  description = "Memory in MiB reserved for the task, as the _monolithic template had it. Worth holding against the instance type: two of these fit on a t3.micro only if nothing else does, which is why the capacity provider is what adds instances during a deployment"

  validation {
    condition     = var.task_memory >= 128
    error_message = "task_memory must be at least 128 MiB."
  }
}
variable "desired_count" {
  type        = number
  default     = 2
  description = "Tasks the service keeps running, as the _monolithic template had it. During a blue/green deployment twice this many run at once, which is what the Auto Scaling group's headroom is for"

  validation {
    condition     = var.desired_count >= 0
    error_message = "desired_count must be zero or greater."
  }
}
variable "scheduling_strategy" {
  type        = string
  default     = "REPLICA"
  description = "How ECS places tasks, as the _monolithic template had it"

  validation {
    condition     = var.scheduling_strategy == "REPLICA"
    error_message = "scheduling_strategy must be REPLICA. DAEMON is rejected with a CODE_DEPLOY deployment controller, and it has no desired count for a blue/green deployment to double."
  }
}
variable "capacity_provider_name" {
  type        = string
  description = "Capacity provider the service places through, by name rather than ARN - see the resource for what an ARN does to every subsequent plan"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9_-]{0,254}$", var.capacity_provider_name))
    error_message = "capacity_provider_name must be a capacity provider name, not an ARN: 1-255 characters of letters, digits, underscores and hyphens."
  }
}
variable "capacity_provider_base" {
  type        = number
  default     = 0
  description = "Tasks placed on that provider before the weighting applies, as the _monolithic template had it"

  validation {
    condition     = var.capacity_provider_base >= 0
    error_message = "capacity_provider_base must be zero or greater."
  }
}
variable "capacity_provider_weight" {
  type        = number
  default     = 1
  description = "Relative share of tasks that provider takes. One provider, so any positive weight is the whole share"

  validation {
    condition     = var.capacity_provider_weight >= 1
    error_message = "capacity_provider_weight must be at least 1. Zero on the only provider in the strategy means the service can never place a task, and ECS reports that as a placement failure rather than a configuration error."
  }
}
variable "blue_target_group_arn" {
  type        = string
  description = "Target group the service registers into at creation. The starting point only: CodeDeploy swaps this field on every deployment, which is why the resource ignores changes to load_balancer (rules.md E-8)"

  validation {
    condition     = can(regex("^arn:aws[a-zA-Z-]*:elasticloadbalancing:", var.blue_target_group_arn))
    error_message = "blue_target_group_arn must be an elasticloadbalancing target group ARN."
  }
}
variable "log_group_name" {
  type        = string
  description = "CloudWatch Logs group the container writes to. The same group the buildspec's generated task definition names, so both revisions log to one place (rules.md B-5)"

  validation {
    condition     = startswith(var.log_group_name, "/")
    error_message = "log_group_name must start with a slash, matching the /ecs/<family> convention the buildspec also uses."
  }
}
variable "log_retention_in_days" {
  type        = number
  default     = 14
  description = "Days log events are kept. The _monolithic template declared the group with no retention, which means never expire - a demo log group that bills forever"

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_in_days)
    error_message = "log_retention_in_days must be one of the retention periods CloudWatch Logs accepts."
  }
}
variable "log_stream_prefix" {
  type        = string
  default     = "ecs"
  description = "Prefix of the log stream names, matching the buildspec's awslogs-stream-prefix"

  validation {
    condition     = length(var.log_stream_prefix) > 0
    error_message = "log_stream_prefix must not be empty. The awslogs driver requires it when the log group is shared by more than one container."
  }
}
variable "container_health_check_interval" {
  type        = number
  default     = 10
  description = "Seconds between the container's own health checks, matching the buildspec's generated task definition"

  validation {
    condition     = var.container_health_check_interval >= 5 && var.container_health_check_interval <= 300
    error_message = "container_health_check_interval must be between 5 and 300 seconds."
  }
}
variable "container_health_check_timeout" {
  type        = number
  default     = 5
  description = "Seconds the container health check command may take, matching the buildspec"

  validation {
    condition     = var.container_health_check_timeout >= 2 && var.container_health_check_timeout <= 60
    error_message = "container_health_check_timeout must be between 2 and 60 seconds."
  }
  validation {
    condition     = var.container_health_check_timeout < var.container_health_check_interval
    error_message = "container_health_check_timeout must be less than container_health_check_interval, or a slow check overlaps the next one."
  }
}
variable "container_health_check_retries" {
  type        = number
  default     = 3
  description = "Consecutive failures before the container is reported unhealthy, matching the buildspec"

  validation {
    condition     = var.container_health_check_retries >= 1 && var.container_health_check_retries <= 10
    error_message = "container_health_check_retries must be between 1 and 10."
  }
}
variable "container_health_check_start_period" {
  type        = number
  default     = 0
  description = "Grace seconds before failed checks start counting, matching the buildspec. Zero suits a Go binary that is listening before the process has finished starting; a slower image needs a real value or ECS kills it during startup"

  validation {
    condition     = var.container_health_check_start_period >= 0 && var.container_health_check_start_period <= 300
    error_message = "container_health_check_start_period must be between 0 and 300 seconds."
  }
}
variable "execution_role_name_prefix" {
  type        = string
  description = "Prefix the task execution role name is generated from"

  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_-]{1,38}$", var.execution_role_name_prefix))
    error_message = "execution_role_name_prefix must be 1-38 characters from the IAM role name character set, leaving room for the generated suffix inside IAM's 64 character limit."
  }
}
variable "execution_role_policy_arns" {
  type        = list(string)
  default     = ["arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"]
  description = "Managed policies attached to the execution role, as the _monolithic template attached. The AWS service-role policy is already scoped to the ECR pull and the log stream calls the agent makes, so replacing it with a hand-written document would be guessing at that list (rules.md A-5)"

  validation {
    condition     = alltrue([for arn in var.execution_role_policy_arns : can(regex("^arn:aws[a-zA-Z-]*:iam::", arn))])
    error_message = "execution_role_policy_arns must contain valid IAM policy ARNs."
  }
  validation {
    condition     = length(var.execution_role_policy_arns) > 0
    error_message = "execution_role_policy_arns must not be empty. With no policy the agent cannot pull the image or open a log stream, and the only symptom is tasks stopping with CannotPullContainerError against an image that is present."
  }
}
variable "security_group_name" {
  type        = string
  description = "Name of the task security group"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.security_group_name)) && !startswith(var.security_group_name, "sg-")
    error_message = "security_group_name must be 1-255 characters from the set AWS accepts for a security group name (a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*, no apostrophe) and must not start with \"sg-\" (rules.md F-1)."
  }
}
variable "security_group_description" {
  type        = string
  default     = "Security group attached to each ECS task network interface under awsvpc networking"
  description = "Description attached to the task security group"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.security_group_description))
    error_message = "security_group_description must be 1-255 characters from the set AWS accepts for a security group description: a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*. An apostrophe is NOT allowed - EC2 rejects CreateSecurityGroup with InvalidParameterValue (rules.md F-1)."
  }
}
variable "ingress_source_security_groups" {
  type        = map(string)
  default     = {}
  description = "Groups allowed to reach the tasks, keyed by a caller-chosen label. The load balancer's group is the only entry this project passes. A map rather than a list because that ID is another module's output, unknown until apply, and for_each needs statically known keys (rules.md B-8)"

  validation {
    condition     = alltrue([for label in keys(var.ingress_source_security_groups) : can(regex("^[a-zA-Z0-9._-]+$", label))])
    error_message = "ingress_source_security_groups keys are labels used in the rule descriptions and resource addresses, so each must be a non-empty string of letters, digits, dots, underscores or hyphens."
  }
  validation {
    condition     = alltrue([for id in values(var.ingress_source_security_groups) : can(regex("^sg-[0-9a-f]+$", id))])
    error_message = "ingress_source_security_groups must contain valid security group IDs (e.g. sg-0123456789abcdef0)."
  }
}
variable "additional_ingress_ports" {
  type        = map(number)
  default     = { https = 443 }
  description = "Ports opened to those sources beyond the container port, keyed by a label. The _monolithic template opened 443 alongside 80 and nothing in this project listens on it - the listener is HTTP and the container serves one port - so the rule is inert. It is reproduced because removing it would change what the original did; set this to {} to drop it"

  validation {
    condition     = alltrue([for label in keys(var.additional_ingress_ports) : can(regex("^[a-zA-Z0-9._-]+$", label))])
    error_message = "additional_ingress_ports keys are labels used in the rule descriptions and resource addresses, so each must be a non-empty string of letters, digits, dots, underscores or hyphens."
  }
  validation {
    condition     = alltrue([for port in values(var.additional_ingress_ports) : port >= 1 && port <= 65535])
    error_message = "additional_ingress_ports values must be between 1 and 65535."
  }
  validation {
    condition     = !contains(keys(var.additional_ingress_ports), "http")
    error_message = "additional_ingress_ports must not use the key \"http\", which is reserved for the rule built from container_port. Two rules under one key would collide in the resource address."
  }
}
variable "enable_ecs_managed_tags" {
  type        = bool
  default     = true
  description = "Whether ECS tags the tasks it launches with the cluster and service they belong to, as the _monolithic template set"
}
variable "enable_service_connect" {
  type        = bool
  default     = false
  description = "Whether the service joins a Service Connect namespace. Off, as the _monolithic template had it, and written out explicitly because an absent block leaves an existing configuration untouched rather than disabling it"
}
