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
  description = <<-DESC
    Region the awslogs driver writes to, which is the region the log group is in. Passed in by the root
    rather than read here with data.aws_region.

    The caller declares this module with depends_on, which defers every data source inside it to apply
    (rules.md D-6). A region read here was therefore unknown at plan whenever anything upstream had
    changes pending, which made container_definitions unknown - and container_definitions forces
    replacement, so each such apply registered a new task definition revision and rolled the service
    with nothing in the task actually different.
  DESC

  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]$", var.region))
    error_message = "region must be a region code such as ap-northeast-1."
  }
}
variable "service_name" {
  type        = string
  description = "Name of the service. No default: CloudFormation generated this name and Terraform requires one, so the caller derives it from the project name"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9_-]{0,254}$", var.service_name))
    error_message = "service_name must be 1-255 characters of letters, digits, underscores and hyphens, starting with a letter or digit."
  }
}
variable "task_family" {
  type        = string
  default     = "amazoncorretto-td"
  description = "Task definition family, as the _monolithic template had it. Each apply that changes the task definition registers a new revision in this family rather than replacing one, so the family is the history"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9_-]{0,254}$", var.task_family))
    error_message = "task_family must be 1-255 characters of letters, digits, underscores and hyphens, starting with a letter or digit."
  }
}
variable "container_name" {
  type        = string
  default     = "core"
  description = "Name of the single container in the task, as the _monolithic template had it. This is the name that appears in the log stream prefix and in every describe-tasks output, so it is what a reader looks for"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9._-]{0,254}$", var.container_name))
    error_message = "container_name must be 1-255 characters of letters, digits, dots, underscores and hyphens, starting with a letter or digit."
  }
}
variable "image_uri" {
  type        = string
  description = <<-DESC
    Full image reference the container pulls, taken from the repository module so that the tag the builder
    pushed and the tag the task pulls are one value (rules.md B-5).

    Nothing validates that this image exists. Registering a task definition does not contact the registry,
    so an image that was never pushed produces a perfectly valid revision, a service that starts tasks,
    and tasks that stop with CannotPullContainerError - repeatedly, since the service keeps replacing
    them. That is the failure mode the caller's image verification step exists to turn into something that
    reports itself.
  DESC

  validation {
    condition     = can(regex("^[a-z0-9][a-zA-Z0-9._/-]*:[a-zA-Z0-9][a-zA-Z0-9._-]*$", var.image_uri))
    error_message = "image_uri must be an image reference including an explicit tag, e.g. 111122223333.dkr.ecr.ap-northeast-2.amazonaws.com/repo:latest. An untagged reference resolves to latest, which makes what runs depend on when it was deployed."
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
  description = "Tasks this provider takes before the weights apply, as the _monolithic template had it. With one provider the value changes nothing"

  validation {
    condition     = var.capacity_provider_base >= 0
    error_message = "capacity_provider_base must be zero or greater."
  }
}
variable "capacity_provider_weight" {
  type        = number
  default     = 1
  description = "Relative share of tasks this provider takes, as the _monolithic template had it. Must be positive while it is the only provider in the strategy: a weight of zero means the strategy can place nothing and the service stays at zero running tasks, reported as an event rather than an error"

  validation {
    condition     = var.capacity_provider_weight >= 1
    error_message = "capacity_provider_weight must be at least 1, because this is the only provider in the service's strategy and a weight of zero would leave the service unable to place any task."
  }
}
variable "desired_count" {
  type        = number
  default     = 2
  description = <<-DESC
    Tasks the service keeps running, as the _monolithic template had it.

    Two rather than one so that the placement strategies do something observable: the first spreads across
    availability zones and the second across instances, which with host networking and a shared bind
    mount is the difference between two tasks writing into one host directory and each having its own.
  DESC

  validation {
    condition     = var.desired_count >= 0
    error_message = "desired_count must be zero or greater."
  }
}
variable "task_cpu" {
  type        = string
  default     = "2048"
  description = <<-DESC
    Task-level CPU units, as the _monolithic template had it. 2048 is two vCPU.

    A string rather than a number because that is what the ECS API takes and what the provider's attribute
    is. Task-level cpu and memory are optional on the EC2 launch type - only Fargate requires them - and
    setting them here is what reserves the capacity on the instance, which is what makes the capacity
    provider's packing decisions mean anything.
  DESC

  validation {
    condition     = can(regex("^[0-9]+$", var.task_cpu))
    error_message = "task_cpu must be a whole number of CPU units expressed as a string, e.g. \"2048\"."
  }
}
variable "task_memory" {
  type        = string
  default     = "15360"
  description = <<-DESC
    Task-level memory in MiB, as the _monolithic template had it. 15360 is 15 GiB.

    This is a hard reservation, and it is the number that decides whether anything runs at all. ECS will
    not place a task on an instance with less memory available than this, and the shortfall is reported as
    a service event - "was unable to place a task because no container instance met all of its
    requirements" - rather than as an error from anything Terraform did. An instance type smaller than
    the task is therefore a configuration that applies cleanly and runs nothing.
  DESC

  validation {
    condition     = can(regex("^[0-9]+$", var.task_memory))
    error_message = "task_memory must be a whole number of MiB expressed as a string, e.g. \"15360\"."
  }
}
variable "network_mode" {
  type        = string
  default     = "host"
  description = <<-DESC
    Task network mode, as the _monolithic template had it.

    host means the container shares the instance's network namespace: no ENI per task, no port mapping,
    and the container's traffic leaves with the instance's own address. This project publishes no ports,
    so what host actually buys here is that the task needs no awsvpc ENI - which is the thing that would
    otherwise limit how many tasks an instance can hold, independently of its CPU and memory.

    It also removes the network_configuration block that awsvpc requires. Switching this to awsvpc without
    adding that block fails at apply with "Network Configuration must be provided when networkMode is
    awsvpc", which at least says so plainly.
  DESC

  validation {
    condition     = contains(["host", "bridge", "awsvpc", "none"], var.network_mode)
    error_message = "network_mode must be one of host, bridge, awsvpc, none."
  }

  validation {
    # awsvpc needs a network_configuration block on the service, which this module does not declare - so
    # it is rejected here with an explanation rather than at apply with a message about a missing block.
    condition     = var.network_mode != "awsvpc"
    error_message = "network_mode cannot be awsvpc in this module, because the service declares no network_configuration block for the subnets and security groups awsvpc requires. host is what the project uses; bridge also works without one."
  }
}
variable "host_volume_path" {
  type        = string
  default     = "/ecs/test"
  description = "Directory on the container instance that the volume points at. The caller passes the same value to the launch template, which creates it (rules.md B-5). This is the subject of the whole project: a bind mount, so the files survive the task and belong to the instance rather than to the container"

  validation {
    condition     = can(regex("^/[^\\s]+$", var.host_volume_path))
    error_message = "host_volume_path must be an absolute path with no whitespace."
  }
}
variable "container_mount_path" {
  type        = string
  default     = "/app/test"
  description = "Path inside the container the volume is mounted at, which is also the path the built image's test script writes into - the caller passes one value to both (rules.md B-5). If they differ the container writes into its own writable layer, the task runs normally, and nothing appears on the host"

  validation {
    condition     = can(regex("^/[^\\s]+$", var.container_mount_path))
    error_message = "container_mount_path must be an absolute path with no whitespace."
  }
}
variable "volume_name" {
  type        = string
  default     = "host-volume"
  description = "Name linking the task's volume declaration to the container's mount point, as the _monolithic template had it. Internal to the task definition. A mount point naming a volume that does not exist is rejected at registration with \"Unknown volume\", which is one of the few mistakes here that does fail loudly"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9._-]{0,254}$", var.volume_name))
    error_message = "volume_name must be 1-255 characters of letters, digits, dots, underscores and hyphens."
  }
}
variable "read_only_volume" {
  type        = bool
  default     = false
  description = "Whether the container gets the mount read-only. False, as the _monolithic template had it, and necessarily so: the container's only job is writing files into this path, and true would make every dd fail with a read-only filesystem while the task itself stayed healthy"
}
variable "log_group_name" {
  type        = string
  description = <<-DESC
    CloudWatch log group the container's awslogs driver writes to.

    No default. The _monolithic template used the literal "/ecs/task", which makes a second copy of this
    project in one account fail at apply with ResourceAlreadyExistsException - and worse, if the first copy
    is destroyed afterwards it takes the group both were using. The caller derives it from the project
    name instead.
  DESC

  validation {
    # The character set CloudWatch Logs accepts, with no anchor on the first character: a leading slash is
    # both allowed and the convention for these names (/ecs/..., /aws/lambda/...), so requiring the name
    # to start with a letter or digit would reject every conventional value.
    condition     = can(regex("^[a-zA-Z0-9_./#-]{1,512}$", var.log_group_name))
    error_message = "log_group_name must be 1-512 characters of letters, digits, underscores, hyphens, slashes, dots and hash signs - the set CloudWatch Logs accepts."
  }
}
variable "log_retention_in_days" {
  type        = number
  default     = 7
  description = <<-DESC
    How long the container's log lines are kept. Null keeps them forever, which is what the
    _monolithic template's bare log group did.

    Seven days rather than forever, because of what this container logs: a dd summary, a du and possibly a
    cleanup line, every second, per task, indefinitely. A group with no retention holds that until someone
    notices the ingestion bill, and nothing about the project reminds them.
  DESC

  validation {
    condition     = var.log_retention_in_days == null || contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_in_days)
    error_message = "log_retention_in_days must be one of the values CloudWatch Logs accepts (1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653) or null to keep logs forever."
  }
}
variable "log_stream_prefix" {
  type        = string
  default     = "amazoncorretto-"
  description = "Prefix the awslogs driver puts on each stream name, as the _monolithic template had it. The full stream is <prefix>/<container>/<task-id>, so this is what makes a stream findable when several task definitions share a group"

  validation {
    condition     = length(var.log_stream_prefix) > 0
    error_message = "log_stream_prefix must not be empty. Without a prefix the awslogs driver names streams by task id alone, which is harder to search and is not what the original did."
  }
}
variable "task_role_policy_arns" {
  type        = list(string)
  default     = ["arn:aws:iam::aws:policy/service-role/AmazonECSInfrastructureRolePolicyForVolumes"]
  description = <<-DESC
    Managed policy ARNs attached to the task role, which is the role the application inside the container
    assumes.

    This is what the _monolithic template attached, and it is kept for fidelity while doing nothing. The
    policy grants EC2 volume operations - CreateVolume, AttachVolume, DescribeVolumes - and exists for the
    ECS infrastructure role that ECS itself assumes when a task definition declares a volume with
    configuredAtLaunch, so that ECS can create and attach an EBS volume per task. That is a different
    feature from this one: the volume here is a bind mount to a directory on the instance, which needs no
    API calls and therefore no permissions at all. The policy is also attached to a role trusted by
    ecs-tasks.amazonaws.com rather than ecs.amazonaws.com, so even the feature it is for could not use it.
    An empty list is the accurate configuration for this task.
  DESC

  validation {
    condition     = alltrue([for arn in var.task_role_policy_arns : can(regex("^arn:aws[a-z-]*:iam::", arn))])
    error_message = "task_role_policy_arns must contain valid IAM policy ARNs, or be empty."
  }
}
variable "task_execution_role_policy_arns" {
  type        = list(string)
  default     = ["arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"]
  description = <<-DESC
    Managed policy ARNs attached to the task execution role, which is the role the ECS agent uses on the
    task's behalf before the container starts.

    AmazonECSTaskExecutionRolePolicy, as the _monolithic template attached. Unlike the task role above,
    this one is doing work: it carries the ECR pull permissions and the logs:CreateLogStream and
    logs:PutLogEvents that the awslogs driver needs. Removing it gives CannotPullContainerError on the
    image, or a task that runs with no log stream ever appearing.
  DESC

  validation {
    condition     = length(var.task_execution_role_policy_arns) > 0 && alltrue([for arn in var.task_execution_role_policy_arns : can(regex("^arn:aws[a-z-]*:iam::", arn))])
    error_message = "task_execution_role_policy_arns must be a non-empty list of IAM policy ARNs. Without the ECR and CloudWatch Logs permissions it carries, the task cannot pull its image or write a log line."
  }
}
variable "scheduling_strategy" {
  type        = string
  default     = "REPLICA"
  description = "How the service places tasks, as the _monolithic template had it. REPLICA keeps desired_count tasks wherever the placement strategies put them; DAEMON would put exactly one on every container instance and ignore desired_count, which for this workload would mean one writer per instance"

  validation {
    condition     = contains(["REPLICA", "DAEMON"], var.scheduling_strategy)
    error_message = "scheduling_strategy must be REPLICA or DAEMON."
  }
}
variable "enable_ecs_managed_tags" {
  type        = bool
  default     = true
  description = "Whether ECS tags the tasks it launches with the cluster and service they belong to, as the _monolithic template had it. On, because without it a task has no tag saying where it came from and the only link back is the ARN"
}
variable "enable_service_connect" {
  type        = bool
  default     = false
  description = "Whether Service Connect is enabled. False, as the _monolithic template had it, and it has to be: this task publishes no ports and uses host networking, so there is nothing to discover. The block is written out explicitly rather than omitted because an existing service with Service Connect on has to be given a disabled block to turn it off - an absent block leaves the previous setting in place"
}
variable "wait_for_steady_state" {
  type        = bool
  default     = false
  description = <<-DESC
    Whether apply waits until the service reports a steady state - desired_count tasks running and no
    deployment in progress.

    False, which is the provider's default and what the _monolithic template effectively had. Worth
    knowing which failure each choice gives, because this is the switch between them. False returns as
    soon as ECS accepts the service, so an image that cannot be pulled or capacity that never arrives is
    something to discover later from the service's events. True holds the apply until the tasks are
    actually running and fails the apply if they do not, naming this resource - which is more useful and
    also means a spot group that cannot get capacity fails the apply rather than the demo.
  DESC
}
