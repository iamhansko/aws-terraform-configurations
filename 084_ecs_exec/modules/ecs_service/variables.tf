variable "cluster_name" {
  type        = string
  description = "Name of the ECS cluster the service runs in, injected rather than looked up (rules.md B-6)"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9_-]{0,254}$", var.cluster_name))
    error_message = "cluster_name must be 1-255 characters of letters, digits, underscores and hyphens."
  }
}
variable "region" {
  type        = string
  description = "Region the awslogs driver writes to, which is the region the log group is in. Passed in by the root rather than read here, because the caller's depends_on would defer a data source in this module to apply and turn container_definitions unknown (rules.md D-6)"

  validation {
    condition     = can(regex("^[a-z]{2}(-gov)?(-[a-z]+)+-[0-9]$", var.region))
    error_message = "region must be a region code such as ap-northeast-2."
  }
}
variable "service_name" {
  type        = string
  description = "Name of the service. No default: CloudFormation generated this name and Terraform requires one, so the caller supplies it. Unique within the cluster; also the stem of the two role name prefixes"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9_-]{0,254}$", var.service_name))
    error_message = "service_name must be 1-255 characters of letters, digits, underscores and hyphens, starting with a letter or digit."
  }
}
variable "subnet_ids" {
  type        = list(string)
  description = "Subnets the task ENIs are placed in. Private subnets with a route to a NAT gateway, as the _monolithic template had it: an ECS Exec session and the Service Connect proxy both call AWS endpoints from inside the task, over the task ENI"

  validation {
    condition     = length(var.subnet_ids) >= 1 && alltrue([for subnet in var.subnet_ids : can(regex("^subnet-[0-9a-f]+$", subnet))])
    error_message = "subnet_ids must contain at least one valid subnet ID (e.g. subnet-0123456789abcdef0)."
  }
}
variable "security_group_ids" {
  type        = list(string)
  description = "Security groups attached to each task ENI. A list is fine here even though the IDs are unknown at plan, because nothing iterates over it - it is passed to network_configuration as a whole (rules.md B-8 applies to for_each only)"

  validation {
    condition     = length(var.security_group_ids) >= 1 && alltrue([for id in var.security_group_ids : can(regex("^sg-[0-9a-f]+$", id))])
    error_message = "security_group_ids must contain at least one valid security group ID (e.g. sg-0123456789abcdef0)."
  }
}
variable "capacity_provider_name" {
  type        = string
  description = "Name of the capacity provider the service places tasks through, injected rather than looked up (rules.md B-6). The name rather than the ARN - see main.tf"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9_-]{0,254}$", var.capacity_provider_name))
    error_message = "capacity_provider_name must be 1-255 characters of letters, digits, underscores and hyphens."
  }
}
variable "capacity_provider_base" {
  type        = number
  default     = 0
  description = "Tasks this provider takes before the weights apply. The _monolithic template left it at the API default of 0; with one provider the value changes nothing"

  validation {
    condition     = var.capacity_provider_base >= 0 && var.capacity_provider_base <= 100000
    error_message = "capacity_provider_base must be between 0 and 100000."
  }
}
variable "capacity_provider_weight" {
  type        = number
  default     = 1
  description = "Relative share of tasks this provider takes, as the _monolithic template had it"

  validation {
    condition     = var.capacity_provider_weight >= 1 && var.capacity_provider_weight <= 1000
    error_message = "capacity_provider_weight must be between 1 and 1000, because this is the only provider in the service's strategy and a weight of zero would leave the service unable to place any task."
  }
}
variable "desired_count" {
  type        = number
  default     = 1
  description = "Tasks the service keeps running"

  validation {
    condition     = var.desired_count >= 0 && floor(var.desired_count) == var.desired_count
    error_message = "desired_count must be a whole number, zero or greater."
  }
}
variable "task_family" {
  type        = string
  description = "Task definition family. Each apply that changes the task definition registers a new revision in this family rather than replacing one, so the family is the history"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9_-]{0,254}$", var.task_family))
    error_message = "task_family must be 1-255 characters of letters, digits, underscores and hyphens, starting with a letter or digit."
  }
}
variable "task_cpu" {
  type        = string
  default     = "256"
  description = "Task-level CPU units, as the _monolithic template had it. A string because that is what the ECS API and the provider attribute take. On the EC2 launch type this is a reservation on the instance, which is what the capacity provider's packing reads"

  validation {
    condition     = can(regex("^[0-9]+$", var.task_cpu)) && try(tonumber(var.task_cpu) >= 128, false)
    error_message = "task_cpu must be a whole number of CPU units of at least 128, expressed as a string, e.g. \"256\"."
  }
}
variable "task_memory" {
  type        = string
  default     = "512"
  description = "Task-level memory in MiB, as the _monolithic template had it. A hard reservation: ECS will not place the task on an instance with less memory left than this. With Service Connect on, the proxy container ECS adds runs inside this same allowance"

  validation {
    condition     = can(regex("^[0-9]+$", var.task_memory)) && try(tonumber(var.task_memory) >= 6, false)
    error_message = "task_memory must be a whole number of MiB of at least 6, expressed as a string, e.g. \"512\"."
  }
}
variable "container_name" {
  type        = string
  description = "Name of the single container in the task. ECS Exec addresses a container by this name (--container), so the root reads it back from this module's output rather than restating it (rules.md B-5)"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9_-]{0,254}$", var.container_name))
    error_message = "container_name must be 1-255 characters of letters, digits, underscores and hyphens, starting with a letter or digit."
  }
}
variable "image" {
  type        = string
  description = "Image reference the container runs"

  validation {
    condition     = can(regex("^[a-z0-9][a-zA-Z0-9._/:@-]*$", var.image)) && length(var.image) <= 255
    error_message = "image must be an image reference such as nginx:latest or registry.k8s.io/e2e-test-images/agnhost:2.50."
  }
}
variable "entry_point" {
  type        = list(string)
  default     = null
  description = "Overrides the image's ENTRYPOINT. Null keeps the image's own, which is right for an image whose default process is long-running; an image that exits on its own needs one, or the service replaces its task forever"

  validation {
    condition     = var.entry_point == null || try(length(var.entry_point) >= 1, false)
    error_message = "entry_point must be a non-empty list of strings, or null to keep the image's own."
  }
}
variable "container_port" {
  type        = number
  default     = null
  description = "Port the container listens on, published as a named port mapping. Null publishes none, which is right for a client that nothing connects to. Required for a Service Connect server, which discovers by port name"

  validation {
    condition     = var.container_port == null || try(var.container_port >= 1 && var.container_port <= 65535 && floor(var.container_port) == var.container_port, false)
    error_message = "container_port must be an integer between 1 and 65535, or null."
  }
}
variable "port_mapping_name" {
  type        = string
  default     = "http"
  description = "Name of the port mapping, as the _monolithic template named it. The Service Connect server block's port_name is taken from this same variable, so the name a service is discovered by always matches a mapping the task definition has"

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,62}[a-z0-9])?$", var.port_mapping_name))
    error_message = "port_mapping_name must be 1-64 lowercase letters, digits and hyphens, not starting or ending with a hyphen."
  }
}
variable "log_group_name" {
  type        = string
  description = "CloudWatch log group the container's awslogs driver writes to, and where ECS Exec sessions are logged. No default: the _monolithic template derived it from the random_uuid standing in for AWS::StackId; the caller derives it from the project name instead"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_./#-]{1,512}$", var.log_group_name))
    error_message = "log_group_name must be 1-512 characters of letters, digits, underscores, hyphens, slashes, dots and hash signs - the set CloudWatch Logs accepts."
  }
}
variable "log_retention_in_days" {
  type        = number
  default     = 7
  description = "How long the container's log lines and the exec session logs are kept. The _monolithic template's log group had no retention, which keeps them forever and bills for it; null restores that"

  validation {
    condition     = var.log_retention_in_days == null || try(contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_in_days), false)
    error_message = "log_retention_in_days must be one of the values CloudWatch Logs accepts (1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653) or null to keep logs forever."
  }
}
variable "log_stream_prefix" {
  type        = string
  description = "Prefix the awslogs driver puts on each stream name. The full stream is <prefix>/<container>/<task-id>"

  validation {
    condition     = can(regex("^[^:*]{1,256}$", var.log_stream_prefix))
    error_message = "log_stream_prefix must be 1-256 characters with no colon or asterisk, which CloudWatch Logs rejects in stream names."
  }
}
variable "enable_execute_command" {
  type        = bool
  default     = false
  description = "Whether ECS Exec is enabled on the service. True also grants the task role the ssmmessages and log permissions a session needs and runs an init process in the container - the three are one feature, so one switch turns them on together"
}
variable "task_role_policy_arns" {
  type        = list(string)
  default     = []
  description = "Managed policy ARNs attached to the task role - what the application inside the container calls AWS with. Empty by default: the ECS Exec permissions are granted separately by enable_execute_command"

  validation {
    condition     = alltrue([for arn in var.task_role_policy_arns : can(regex("^arn:aws[a-z-]*:iam::", arn))])
    error_message = "task_role_policy_arns must contain valid IAM policy ARNs, or be empty."
  }
}
variable "task_execution_role_policy_arns" {
  type        = list(string)
  default     = ["arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"]
  description = "Managed policy ARNs attached to the task execution role, as the _monolithic template attached. AmazonECSTaskExecutionRolePolicy carries the ECR pull permissions and the logs:CreateLogStream and logs:PutLogEvents the awslogs driver needs"

  validation {
    condition     = length(var.task_execution_role_policy_arns) > 0 && alltrue([for arn in var.task_execution_role_policy_arns : can(regex("^arn:aws[a-z-]*:iam::", arn))])
    error_message = "task_execution_role_policy_arns must be a non-empty list of IAM policy ARNs. Without the ECR and CloudWatch Logs permissions it carries, the task cannot pull its image or write a log line."
  }
}
variable "service_connect" {
  type = object({
    namespace = optional(string)
    server = optional(object({
      discovery_name        = string
      client_alias_dns_name = string
      client_alias_port     = number
    }))
  })
  default     = null
  description = <<-DESC
    Service Connect configuration. Null disables it, which is what a service outside a Service Connect
    namespace should have.

    namespace is the Cloud Map namespace the service joins; null joins the cluster's default namespace, as
    the _monolithic template of 085_ecs_service_connect did for both of its services. server makes the
    service reachable by other services in the namespace at client_alias_dns_name:client_alias_port, on the
    port mapping named port_mapping_name; without it the service is a client only.

    A client task learns the namespace's endpoints when it starts, and only then. A client started before a
    server's endpoint existed cannot reach it until the client is redeployed, so the caller orders client
    services after the servers they call.
  DESC

  validation {
    condition     = var.service_connect == null || try(var.service_connect.server == null, true) || var.container_port != null
    error_message = "service_connect.server requires container_port, because a Service Connect endpoint is a named port mapping of the task definition and there is none without a port."
  }

  validation {
    condition     = var.service_connect == null || try(var.service_connect.server == null, true) || try(can(regex("^[a-z0-9]([a-z0-9-]{0,62}[a-z0-9])?$", var.service_connect.server.discovery_name)) && var.service_connect.server.client_alias_port >= 1 && var.service_connect.server.client_alias_port <= 65535 && can(regex("^[a-z0-9_]([a-z0-9_.-]{0,125}[a-z0-9_])?$", var.service_connect.server.client_alias_dns_name)), false)
    error_message = "service_connect.server needs a discovery_name of 1-64 lowercase letters, digits and hyphens, a client_alias_dns_name of up to 127 lowercase letters, digits, underscores, hyphens and periods such as nginx.local, and a client_alias_port between 1 and 65535."
  }

  validation {
    condition     = var.service_connect == null || try(var.service_connect.namespace == null, true) || try(length(var.service_connect.namespace) <= 1024 && can(regex("^(arn:aws[a-z-]*:servicediscovery:.+|[a-zA-Z0-9._-]+)$", var.service_connect.namespace)), false)
    error_message = "service_connect.namespace must be a Cloud Map namespace ARN or name, or null to join the cluster's default namespace."
  }
}
variable "service_registry" {
  type = object({
    registry_arn = string
  })
  default     = null
  description = "Cloud Map service the tasks register their ENI addresses in, for discovery by DNS. Null registers nothing. An object rather than a bare ARN so that whether the registration exists is known at plan even while the ARN is not"

  validation {
    condition     = var.service_registry == null || can(regex("^arn:aws[a-z-]*:servicediscovery:", var.service_registry.registry_arn))
    error_message = "service_registry.registry_arn must be the ARN of a Cloud Map service (arn:aws:servicediscovery:...), or service_registry must be null."
  }
}
variable "placement_strategies" {
  type = list(object({
    type  = string
    field = optional(string)
  }))
  default     = []
  description = "Ordered placement strategies, applied in sequence. Empty, as the _monolithic template had it, which leaves ECS to its default of spreading a service's tasks across Availability Zones"

  validation {
    condition     = length(var.placement_strategies) <= 5 && alltrue([for strategy in var.placement_strategies : contains(["binpack", "random", "spread"], strategy.type)])
    error_message = "placement_strategies may hold at most five entries, each of type binpack, random or spread."
  }
}
variable "enable_ecs_managed_tags" {
  type        = bool
  default     = false
  description = "Whether ECS tags the tasks it launches with the cluster and service they belong to. False, as the _monolithic template had it by not setting it"
}
variable "wait_for_steady_state" {
  type        = bool
  default     = false
  description = "Whether apply waits until the service reports a steady state. False, the provider default: apply returns once ECS accepts the service, and a task that cannot start is something to read from the service events afterwards. True holds the apply until the tasks run and fails it, naming this resource, if they do not"
}
