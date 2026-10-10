variable "vpc_id" {
  type        = string
  description = "VPC ID where the container instance security group is created"
  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must be a valid VPC ID (e.g. vpc-0123456789abcdef0)."
  }
}
variable "subnet_ids" {
  type        = list(string)
  description = "Subnets the Auto Scaling group places instances in. They have to be public subnets in this project: there is no NAT gateway, so an instance on a subnet without a route to the internet gateway can neither register with ECS nor deliver a log record"
  validation {
    condition     = length(var.subnet_ids) >= 1 && alltrue([for subnet in var.subnet_ids : can(regex("^subnet-[0-9a-f]+$", subnet))])
    error_message = "subnet_ids must contain at least one valid subnet ID (e.g. subnet-0123456789abcdef0)."
  }
}
variable "cluster_name" {
  type        = string
  description = "Name of the ECS cluster the instances join and the capacity provider is attached to. Taken as a name rather than looked up, so this module does not have to know how the cluster was created (rules.md B-6). The launch template userdata writes it into /etc/ecs/ecs.config, which is the only thing that makes an instance join this cluster rather than the one called \"default\""
  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9_-]{0,254}$", var.cluster_name))
    error_message = "cluster_name must be 1-255 characters of letters, digits, underscores and hyphens, starting with a letter or digit."
  }
}
variable "ami_id" {
  type        = string
  description = "AMI ID for the container instances. Resolved from the ECS-optimized AMI's SSM public parameter by the root rather than by this module, so the read happens at plan time rather than being deferred to apply by the module's depends_on (rules.md D-6). It has to be an ECS-optimized AMI or an AMI carrying ecs-init: that package is what puts the agent, the awslogs logging driver and the execution-role override in place, and all three are load-bearing here"
  validation {
    condition     = can(regex("^ami-[0-9a-f]+$", var.ami_id))
    error_message = "ami_id must be a valid AMI ID (e.g. ami-0123456789abcdef0)."
  }
}
variable "instance_type" {
  type        = string
  default     = "t3.medium"
  description = "Instance type for the container instances, as the _monolithic template had it. One t3.medium holds both tasks: the task definition reserves 512 CPU units and 1024 MiB each, against roughly 2048 units and 3.8 GiB that ECS registers for this type. Anything smaller leaves the second task pending with max_size at 1"
  validation {
    condition     = can(regex("^[a-z0-9]+\\.[a-z0-9]+$", var.instance_type))
    error_message = "instance_type must be a valid EC2 instance type (e.g. t3.medium)."
  }
}
variable "key_name" {
  type        = string
  default     = null
  description = "Optional EC2 key pair name the instances are launched with, as the _monolithic template passed. When null, they are reachable only over SSM Session Manager"
  validation {
    condition     = var.key_name == null || can(regex("^[ -~]{1,255}$", var.key_name))
    error_message = "key_name must be a string of printable ASCII characters (255 or fewer), or null."
  }
}
variable "instance_name" {
  type        = string
  default     = "ecs-container-instance"
  description = "Name tag for the instances, and the prefix of the generated launch template and Auto Scaling group names. As the _monolithic template tagged them"
  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9._-]{0,99}$", var.instance_name))
    error_message = "instance_name must be 1-100 characters of letters, digits, dots, underscores and hyphens, starting with a letter or digit, because it is also used as a name prefix."
  }
}
variable "instance_profile_name_prefix" {
  type        = string
  default     = "ContainerInstanceProfile-"
  description = "Prefix for the generated instance profile name. The _monolithic template built \"ContainerInstanceProfile-<uuid slice>\" from its stand-in for AWS::StackId; a provider-generated suffix gets the same uniqueness without the random provider"
  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_-]{1,96}$", var.instance_profile_name_prefix))
    error_message = "instance_profile_name_prefix must be 1-96 characters of the set IAM accepts for an instance profile name, leaving room for the generated suffix inside the 128 character limit."
  }
}
variable "security_group_name" {
  type        = string
  default     = "ecs-container-instance-sg"
  description = "Name of the security group attached to the container instances, as the _monolithic template named it. With bridge networking the tasks share this group, so it is also the group every Fluent Bit delivery leaves through"
  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.security_group_name)) && !startswith(var.security_group_name, "sg-")
    error_message = "security_group_name must be 1-255 characters from the set AWS accepts for a security group name (a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*, no apostrophe) and must not start with \"sg-\", which EC2 reserves for security group IDs."
  }
}
variable "security_group_description" {
  type        = string
  default     = "Security group for the ECS container instances and the tasks sharing their network namespace"
  description = "Description attached to the security group. Changing it replaces the group, because AWS has no API for editing a group description (rules.md F-1)"
  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.security_group_description))
    error_message = "security_group_description must be 1-255 characters from the set AWS accepts for a security group description: a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*. An apostrophe is NOT allowed - EC2 rejects CreateSecurityGroup with InvalidParameterValue, which otherwise only surfaces at apply time (rules.md F-1)."
  }
}
variable "ingress_source_security_groups" {
  type        = map(string)
  default     = {}
  description = "Security group IDs allowed all inbound traffic, keyed by a caller-chosen label. A map rather than a list because these IDs are another module's output and are unknown until apply, while a for_each key has to be known at plan time (rules.md B-8). Empty by default - nothing in this project reaches the tasks inbound"
  validation {
    condition     = alltrue([for label in keys(var.ingress_source_security_groups) : can(regex("^[a-zA-Z0-9._-]+$", label))])
    error_message = "ingress_source_security_groups keys are labels used in the rule descriptions and resource addresses, so each must be a non-empty string of letters, digits, dots, underscores or hyphens - the character set a security group description also accepts (rules.md F-1)."
  }
  validation {
    condition     = alltrue([for id in values(var.ingress_source_security_groups) : can(regex("^sg-[0-9a-f]+$", id))])
    error_message = "ingress_source_security_groups must contain valid security group IDs (e.g. sg-0123456789abcdef0)."
  }
}
variable "iam_policy_arns" {
  type = list(string)
  default = [
    "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role",
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
  ]
  description = <<-DESC
    Managed policy ARNs attached to the container instance role, which is what the two numbered
    attachments in the _monolithic template attached.
    Both are doing work. AmazonEC2ContainerServiceforEC2Role carries RegisterContainerInstance and the
    agent's poll, the ECR pull actions, and logs:CreateLogStream plus logs:PutLogEvents - note that it
    does not carry logs:CreateLogGroup, which is one of the reasons the log groups are declared in
    Terraform rather than created at runtime. AmazonSSMManagedInstanceCore is what makes these instances
    reachable over Session Manager, which is the only way onto them.
  DESC
  validation {
    condition     = length(var.iam_policy_arns) > 0 && alltrue([for arn in var.iam_policy_arns : can(regex("^arn:aws[a-z-]*:iam::", arn))])
    error_message = "iam_policy_arns must be a non-empty list of IAM policy ARNs. Without AmazonEC2ContainerServiceforEC2Role the agent's RegisterContainerInstance call is denied and the instance never joins the cluster."
  }
}
variable "ecs_config_options" {
  type        = map(string)
  default     = {}
  description = <<-DESC
    Extra key/value pairs appended to /etc/ecs/ecs.config alongside ECS_CLUSTER, which the agent reads
    once at startup. ECS_CLUSTER is always written from cluster_name and must not appear here.
    Empty by default, and that is a finding rather than an omission: the two agent settings this project
    depends on - awslogs among the available logging drivers, and
    ECS_ENABLE_AWSLOGS_EXECUTIONROLE_OVERRIDE - both come from the ECS-optimized AMI's ecs-init package
    rather than from this file. On a custom AMI they would have to be set here, and getting the first one
    wrong makes the task unplaceable rather than producing an error about logging.
    ECS_LOGLEVEL=debug is the useful entry when the agent's own behaviour is in question.
  DESC
  validation {
    condition     = alltrue([for key in keys(var.ecs_config_options) : can(regex("^ECS_[A-Z0-9_]+$", key))])
    error_message = "ecs_config_options keys must be ECS agent configuration variables (ECS_ followed by uppercase letters, digits and underscores)."
  }
  validation {
    condition     = !contains(keys(var.ecs_config_options), "ECS_CLUSTER")
    error_message = "ECS_CLUSTER must not be set here. It is written from cluster_name, which is also what the capacity provider association uses, so setting it twice is how an instance ends up in a different cluster from the one the service is in."
  }
  validation {
    condition     = alltrue([for value in values(var.ecs_config_options) : !can(regex("[\n\r]", value))])
    error_message = "ecs_config_options values must not contain newlines, because each pair is written as a single key=value line in /etc/ecs/ecs.config."
  }
}
variable "min_size" {
  type        = number
  default     = 1
  description = "Minimum size of the Auto Scaling group, as the _monolithic template had it"
  validation {
    condition     = var.min_size >= 0
    error_message = "min_size must be zero or greater."
  }
}
variable "max_size" {
  type        = number
  default     = 1
  description = "Maximum size of the Auto Scaling group, as the _monolithic template had it. At 1 the capacity provider's managed scaling has nowhere to go, which is fine here only because both tasks fit on one instance of instance_type - raise this before raising the service's desired count"
  validation {
    condition     = var.max_size >= 1
    error_message = "max_size must be at least 1."
  }
  validation {
    condition     = var.max_size >= var.min_size
    error_message = "max_size must be greater than or equal to min_size."
  }
}
variable "desired_capacity" {
  type        = number
  default     = 1
  description = "Instances the group starts with, as the _monolithic template had it. The starting point only: with managed scaling enabled, ECS owns this field afterwards, which is why the resource ignores changes to it"
  validation {
    condition     = var.desired_capacity >= var.min_size && var.desired_capacity <= var.max_size
    error_message = "desired_capacity must be between min_size and max_size inclusive."
  }
}
variable "capacity_provider_name" {
  type        = string
  description = "Name of the capacity provider. No default: CloudFormation generated this name and Terraform requires one, so the caller derives it from the project name"
  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9_-]{0,254}$", var.capacity_provider_name))
    error_message = "capacity_provider_name must be 1-255 characters of letters, digits, underscores and hyphens, starting with a letter or digit."
  }
  validation {
    condition     = !can(regex("^(aws|ecs|fargate)", lower(var.capacity_provider_name)))
    error_message = "capacity_provider_name must not start with aws, ecs or fargate, which ECS reserves. It rejects the name at apply time with InvalidParameterException; plan does not check it."
  }
}
variable "managed_scaling_status" {
  type        = string
  default     = "ENABLED"
  description = "Whether ECS scales the Auto Scaling group from the tasks waiting to be placed. The _monolithic template left the whole managed_scaling block out and took the API's default, which is this; stating it is what makes the ignore_changes on desired_capacity legible"
  validation {
    condition     = contains(["ENABLED", "DISABLED"], var.managed_scaling_status)
    error_message = "managed_scaling_status must be ENABLED or DISABLED."
  }
}
variable "managed_scaling_target_capacity" {
  type        = number
  default     = 100
  description = "Percentage of the group's capacity ECS aims to keep in use. 100 means scale only when a task cannot be placed"
  validation {
    condition     = var.managed_scaling_target_capacity >= 1 && var.managed_scaling_target_capacity <= 100
    error_message = "managed_scaling_target_capacity must be between 1 and 100."
  }
}
variable "managed_scaling_instance_warmup_period" {
  type        = number
  default     = 300
  description = "Seconds ECS waits before counting a newly launched instance towards capacity, which is the API's own default"
  validation {
    condition     = var.managed_scaling_instance_warmup_period >= 0
    error_message = "managed_scaling_instance_warmup_period must be zero or greater."
  }
}
variable "managed_termination_protection" {
  type        = string
  default     = "DISABLED"
  description = "Whether ECS protects instances running tasks from scale-in. Enabling it requires protect_from_scale_in on the group as well, and the pair is validated below - ECS rejects the mismatched combination at apply time"
  validation {
    condition     = contains(["ENABLED", "DISABLED"], var.managed_termination_protection)
    error_message = "managed_termination_protection must be ENABLED or DISABLED."
  }
  validation {
    # Cross-variable condition, available since Terraform 1.9. The constraint is about the three values
    # together rather than about any one of them (rules.md B-1).
    condition     = var.managed_termination_protection == "DISABLED" || (var.protect_from_scale_in && var.managed_scaling_status == "ENABLED")
    error_message = "managed_termination_protection can only be ENABLED when protect_from_scale_in is true and managed_scaling_status is ENABLED. ECS rejects the other combinations at apply time."
  }
}
variable "protect_from_scale_in" {
  type        = bool
  default     = false
  description = "Whether the Auto Scaling group protects its instances from scale-in. The group-side half of managed_termination_protection; the two are validated as a pair above"
}
variable "managed_draining" {
  type        = string
  default     = "ENABLED"
  description = "Whether ECS drains tasks off an instance that is terminating, rather than letting them stop with it"
  validation {
    condition     = contains(["ENABLED", "DISABLED"], var.managed_draining)
    error_message = "managed_draining must be ENABLED or DISABLED."
  }
}
variable "default_strategy_base" {
  type        = number
  default     = 0
  description = "Tasks the cluster's default strategy places on this provider before applying the weight, as the _monolithic template had it"
  validation {
    condition     = var.default_strategy_base >= 0
    error_message = "default_strategy_base must be zero or greater."
  }
}
variable "default_strategy_weight" {
  type        = number
  default     = 100
  description = "Relative share of tasks the cluster's default strategy sends to this provider, as the _monolithic template had it. There is only one provider, so any positive value means all of them"
  validation {
    condition     = var.default_strategy_weight >= 0
    error_message = "default_strategy_weight must be zero or greater."
  }
}
