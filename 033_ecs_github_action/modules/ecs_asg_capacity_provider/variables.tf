variable "vpc_id" {
  type        = string
  description = "VPC ID where the container instances' security group is created"

  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must be a valid VPC ID (e.g. vpc-0123456789abcdef0)."
  }
}
variable "subnet_ids" {
  type        = list(string)
  description = "Private subnets the Auto Scaling group places instances in. Private is what the _monolithic template had, so outbound goes through the NAT gateways - the ECS agent cannot register an instance it cannot reach the ECS endpoint from"

  validation {
    condition     = length(var.subnet_ids) >= 1 && alltrue([for id in var.subnet_ids : can(regex("^subnet-[0-9a-f]+$", id))])
    error_message = "subnet_ids must contain at least one valid subnet ID (e.g. subnet-0123456789abcdef0)."
  }
}
variable "cluster_name" {
  type        = string
  description = "Name of the ECS cluster. Written into /etc/ecs/ecs.config on each instance and used for the cluster-to-provider association, so both come from the cluster module's output rather than being restated (rules.md B-5)"

  validation {
    condition     = length(var.cluster_name) > 0
    error_message = "cluster_name must not be empty."
  }
}
variable "ami_id" {
  type        = string
  description = "AMI ID for the container instances. The caller resolves the ECS-optimized AMI parameter and passes the ID, so this module does not have to know where it came from (rules.md B-6) and the read stays out of a module that carries depends_on (rules.md D-6)"

  validation {
    condition     = can(regex("^ami-[0-9a-f]+$", var.ami_id))
    error_message = "ami_id must be a valid AMI ID (e.g. ami-0123456789abcdef0)."
  }
}
variable "key_name" {
  type        = string
  default     = null
  description = "Optional EC2 key pair name attached to the launched instances"

  validation {
    condition     = var.key_name == null || can(regex("^[ -~]{1,255}$", var.key_name))
    error_message = "key_name must be a string of printable ASCII characters (255 or fewer), or null."
  }
}
variable "capacity_provider_name" {
  type        = string
  description = "Name of the ECS capacity provider. CloudFormation generated this name; Terraform requires one, so the caller derives it. The generated appspec names this provider for the replacement task set, so the two cannot differ (rules.md B-5)"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9_-]{0,254}$", var.capacity_provider_name))
    error_message = "capacity_provider_name must be 1-255 characters of letters, digits, underscores or hyphens, starting with a letter or digit."
  }
  validation {
    condition     = !startswith(lower(var.capacity_provider_name), "aws") && !startswith(lower(var.capacity_provider_name), "ecs") && !startswith(lower(var.capacity_provider_name), "fargate")
    error_message = "capacity_provider_name must not start with aws, ecs or fargate - ECS reserves those prefixes and rejects CreateCapacityProvider with a ClientException."
  }
}
variable "instance_name" {
  type        = string
  default     = "ecs-container-instance"
  description = "Name tag for the container instances, also the prefix of the launch template and Auto Scaling group names"

  validation {
    condition     = length(var.instance_name) > 0
    error_message = "instance_name must not be empty."
  }
}
variable "instance_type" {
  type        = string
  default     = "t3.medium"
  description = "Instance type for the container instances, as the _monolithic template had it. It also sets the ENI budget: the task definition uses awsvpc, so each task takes an ENI of its own on top of the instance's, and a blue/green cutover briefly runs two task sets at once"

  validation {
    condition     = can(regex("^[a-z0-9]+\\.[a-z0-9]+$", var.instance_type))
    error_message = "instance_type must be a valid EC2 instance type (e.g. t3.medium)."
  }
}
variable "security_group_name" {
  type        = string
  default     = "ecs-container-instance-sg"
  description = "Name of the container instances' security group, as the _monolithic template named it"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.security_group_name)) && !startswith(var.security_group_name, "sg-")
    error_message = "security_group_name must be 1-255 characters from the set AWS accepts for a security group name (a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*, no apostrophe) and must not start with \"sg-\", which EC2 reserves for security group IDs."
  }
}
variable "security_group_description" {
  type        = string
  default     = "Security group for the ECS container instances behind the EC2 capacity provider"
  description = "Description attached to the container instances' security group"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.security_group_description))
    error_message = "security_group_description must be 1-255 characters from the set AWS accepts for a security group description: a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*. An apostrophe is NOT allowed - EC2 rejects CreateSecurityGroup with InvalidParameterValue, and changing this value replaces the group (rules.md F-1)."
  }
}
variable "revoke_rules_on_delete" {
  type        = bool
  default     = true
  description = "Whether Terraform revokes this group's attached rules before deleting it. Only changes Terraform's delete behaviour - it does not replace the group (rules.md F-2)"
}
variable "ingress_source_security_groups" {
  type        = map(string)
  default     = {}
  description = "Security group IDs allowed all inbound traffic, keyed by a caller-chosen label. A map rather than a list because these IDs are another module's output and unknown until apply, and for_each needs statically known keys (rules.md B-8)"

  validation {
    condition     = alltrue([for label in keys(var.ingress_source_security_groups) : can(regex("^[a-zA-Z0-9._-]+$", label))])
    error_message = "ingress_source_security_groups keys appear in the rule descriptions and in the resource addresses, so each must be a non-empty string of letters, digits, dots, underscores or hyphens."
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
  description = "IAM managed policy ARNs attached to the container instances' role, as the _monolithic template attached them. The first is what RegisterContainerInstance and the ECR pull need; the second is for Session Manager onto a box that failed to register"

  validation {
    condition     = alltrue([for arn in var.iam_policy_arns : can(regex("^arn:aws:iam::", arn))])
    error_message = "iam_policy_arns must contain valid IAM policy ARNs."
  }
}
variable "ecs_config_options" {
  type        = map(string)
  default     = {}
  description = "Extra KEY=VALUE lines written into /etc/ecs/ecs.config alongside ECS_CLUSTER. Empty by default, as the _monolithic template had it"

  validation {
    condition     = alltrue([for key in keys(var.ecs_config_options) : can(regex("^[A-Z0-9_]+$", key))])
    error_message = "ecs_config_options keys must be upper-case ECS agent variable names (e.g. ECS_ENABLE_TASK_IAM_ROLE)."
  }
}
variable "min_size" {
  type        = number
  default     = 1
  description = "Minimum number of container instances, as the _monolithic template had it"

  validation {
    condition     = var.min_size >= 0
    error_message = "min_size must be zero or greater."
  }
}
variable "max_size" {
  type        = number
  default     = 2
  description = "Maximum number of container instances. Two rather than the _monolithic template's one, which is a deliberate change: a blue/green deployment runs the replacement task set alongside the original one, and with a ceiling of one instance ECS managed scaling has nowhere to put it if it does not fit. The deployment then stalls reporting that no container instance met the task's requirements, which reads as a placement constraint problem"

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
  description = "Starting number of container instances, as the _monolithic template had it. A starting point only: managed scaling owns this field afterwards, which is why the group ignores changes to it"

  validation {
    condition     = var.desired_capacity >= 0
    error_message = "desired_capacity must be zero or greater."
  }
  validation {
    condition     = var.desired_capacity >= var.min_size && var.desired_capacity <= var.max_size
    error_message = "desired_capacity must be between min_size and max_size."
  }
}
variable "capacity_distribution_strategy" {
  type        = string
  default     = "balanced-only"
  description = "How the Auto Scaling group spreads instances across the zones, as the _monolithic template had it"

  validation {
    condition     = contains(["balanced-only", "balanced-best-effort"], var.capacity_distribution_strategy)
    error_message = "capacity_distribution_strategy must be balanced-only or balanced-best-effort."
  }
}
variable "root_device_name" {
  type        = string
  default     = "/dev/xvda"
  description = "Root device name of the ECS-optimized AMI, which the block device mapping resizes"

  validation {
    condition     = can(regex("^/dev/", var.root_device_name))
    error_message = "root_device_name must be a device path starting with /dev/."
  }
}
variable "root_volume_size" {
  type        = number
  default     = 30
  description = "Size in GiB of each container instance's root volume, which is also where pulled image layers land"

  validation {
    condition     = var.root_volume_size >= 30
    error_message = "root_volume_size must be at least 30 GiB, which is the ECS-optimized AMI's own root volume size - a smaller value is rejected at launch."
  }
}
variable "root_volume_type" {
  type        = string
  default     = "gp3"
  description = "Root volume type. gp3 rather than the ECS-optimized AMI's gp2 default, which ties throughput to volume size"

  validation {
    condition     = contains(["gp2", "gp3"], var.root_volume_type)
    error_message = "root_volume_type must be gp2 or gp3."
  }
}
variable "protect_from_scale_in" {
  type        = bool
  default     = false
  description = "Whether instances are protected from scale-in. The group-side half of managed_termination_protection, which ECS validates as a pair - false here because the _monolithic template disabled that setting"
}
variable "managed_draining" {
  type        = string
  default     = "ENABLED"
  description = "Whether ECS drains tasks off an instance the Auto Scaling group is terminating, as the _monolithic template had it"

  validation {
    condition     = contains(["ENABLED", "DISABLED"], var.managed_draining)
    error_message = "managed_draining must be ENABLED or DISABLED."
  }
}
variable "managed_termination_protection" {
  type        = string
  default     = "DISABLED"
  description = "Whether ECS protects instances running tasks from scale-in, as the _monolithic template had it. Enabling it also requires protect_from_scale_in to be true"

  validation {
    condition     = contains(["ENABLED", "DISABLED"], var.managed_termination_protection)
    error_message = "managed_termination_protection must be ENABLED or DISABLED."
  }
  validation {
    condition     = var.managed_termination_protection == "DISABLED" || var.protect_from_scale_in
    error_message = "managed_termination_protection ENABLED requires protect_from_scale_in to be true. ECS validates the pair and rejects CreateCapacityProvider otherwise."
  }
}
variable "managed_scaling_status" {
  type        = string
  default     = "ENABLED"
  description = "Whether ECS moves the Auto Scaling group's desired count to fit the tasks waiting to be placed, as the _monolithic template had it"

  validation {
    condition     = contains(["ENABLED", "DISABLED"], var.managed_scaling_status)
    error_message = "managed_scaling_status must be ENABLED or DISABLED."
  }
}
variable "managed_scaling_target_capacity" {
  type        = number
  default     = 100
  description = "Target percentage of the group's capacity ECS aims to keep in use, as the _monolithic template had it. 100 means it adds an instance only once the existing ones are full"

  validation {
    condition     = var.managed_scaling_target_capacity >= 1 && var.managed_scaling_target_capacity <= 100
    error_message = "managed_scaling_target_capacity must be between 1 and 100."
  }
}
variable "managed_scaling_instance_warmup_period" {
  type        = number
  default     = 30
  description = "Seconds ECS waits before counting a newly launched instance towards capacity, as the _monolithic template had it"

  validation {
    condition     = var.managed_scaling_instance_warmup_period >= 0 && var.managed_scaling_instance_warmup_period <= 10000
    error_message = "managed_scaling_instance_warmup_period must be between 0 and 10000 seconds."
  }
}
variable "managed_scaling_minimum_step_size" {
  type        = number
  default     = 1
  description = "Smallest number of instances ECS adds or removes in one step, as the _monolithic template had it"

  validation {
    condition     = var.managed_scaling_minimum_step_size >= 1 && var.managed_scaling_minimum_step_size <= 10000
    error_message = "managed_scaling_minimum_step_size must be between 1 and 10000."
  }
}
variable "managed_scaling_maximum_step_size" {
  type        = number
  default     = 10000
  description = "Largest number of instances ECS adds or removes in one step, as the _monolithic template had it. max_size is the real ceiling"

  validation {
    condition     = var.managed_scaling_maximum_step_size >= 1 && var.managed_scaling_maximum_step_size <= 10000
    error_message = "managed_scaling_maximum_step_size must be between 1 and 10000."
  }
  validation {
    condition     = var.managed_scaling_maximum_step_size >= var.managed_scaling_minimum_step_size
    error_message = "managed_scaling_maximum_step_size must be greater than or equal to managed_scaling_minimum_step_size."
  }
}
variable "additional_capacity_providers" {
  type        = list(string)
  default     = ["FARGATE", "FARGATE_SPOT"]
  description = "Capacity providers attached to the cluster alongside the EC2 one, as the _monolithic template attached them. Neither is used by the service, which places with launch_type EC2 - they are what makes the workflow's Fargate branch possible, where the appspec names FARGATE for the replacement task set"

  validation {
    condition     = alltrue([for name in var.additional_capacity_providers : contains(["FARGATE", "FARGATE_SPOT"], name)])
    error_message = "additional_capacity_providers may only contain FARGATE and FARGATE_SPOT. Any other provider has to be created first, and this module only creates the EC2 one."
  }
}
variable "default_strategy_base" {
  type        = number
  default     = 0
  description = "Number of tasks the default strategy places on the EC2 provider before applying weights, as the _monolithic template had it"

  validation {
    condition     = var.default_strategy_base >= 0
    error_message = "default_strategy_base must be zero or greater."
  }
}
variable "default_strategy_weight" {
  type        = number
  default     = 100
  description = "Relative weight of the EC2 provider in the cluster's default strategy, as the _monolithic template had it. It is the only weighted entry, so every task without its own strategy lands here"

  validation {
    condition     = var.default_strategy_weight >= 0
    error_message = "default_strategy_weight must be zero or greater."
  }
}
