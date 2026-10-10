variable "vpc_id" {
  type        = string
  description = "VPC the container instance security group is created in"

  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must be a valid VPC ID (e.g. vpc-0123456789abcdef0)."
  }
}
variable "subnet_ids" {
  type        = list(string)
  description = "Subnets the Auto Scaling group places instances in. Private ones, so outbound goes through the NAT gateways - the ECS agent cannot register an instance it cannot reach the ECS endpoint from"

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
  description = "Cluster the agent is told to join and the capacity provider is attached to. Taken by the caller from the cluster module's output, so this name and the one the service uses are one value (rules.md B-5)"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,255}$", var.cluster_name))
    error_message = "cluster_name must be 1-255 characters of letters, digits, underscores and hyphens."
  }
}
variable "ami_id" {
  type        = string
  description = "AMI the container instances launch from. An ECS-optimized image, resolved in the root from a public SSM parameter and passed in so this module does not have to know where it came from (rules.md B-6)"

  validation {
    condition     = can(regex("^ami-[0-9a-f]+$", var.ami_id))
    error_message = "ami_id must be a valid AMI ID (e.g. ami-0123456789abcdef0). If the SSM parameter lookup in the root is returning something else, this is where it shows up."
  }
}
variable "key_name" {
  type        = string
  description = "Key pair placed on the container instances, which is what makes the SSH rule from the bastion usable"

  validation {
    condition     = length(var.key_name) > 0
    error_message = "key_name must not be empty."
  }
}
variable "capacity_provider_name" {
  type        = string
  description = "Name of the capacity provider. The cluster's default strategy, the service's strategy and the CodeBuild buildspec's appspec all name it"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9_-]{0,254}$", var.capacity_provider_name)) && !startswith(lower(var.capacity_provider_name), "aws") && !startswith(lower(var.capacity_provider_name), "fargate")
    error_message = "capacity_provider_name must be 1-255 characters of letters, digits, underscores and hyphens, start with a letter or digit, and must not start with \"aws\" or \"fargate\", which ECS reserves."
  }
}
variable "instance_name" {
  type        = string
  description = "Name tag placed on each container instance"

  validation {
    condition     = length(var.instance_name) > 0
    error_message = "instance_name must not be empty."
  }
}
variable "security_group_name" {
  type        = string
  description = "Name of the container instances' security group. The _monolithic template named it \"asg-sg\" with no prefix, which collides with the other projects in this repository, so the caller prefixes it"

  validation {
    # Changing this replaces the group, and a group cannot be deleted while another group's rule still
    # references it - so a typo here is expensive to correct later rather than merely wrong (rules.md F-1).
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.security_group_name)) && !startswith(var.security_group_name, "sg-")
    error_message = "security_group_name must be 1-255 characters from the set AWS accepts for a security group name (a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*, no apostrophe) and must not start with \"sg-\", which EC2 reserves for security group IDs."
  }
}
variable "security_group_description" {
  type        = string
  default     = "Container instances registered with the ECS cluster by the capacity provider"
  description = "Description attached to that security group. EC2 has no API to change it, so editing this replaces the group"

  validation {
    # An apostrophe is the trap here: it reads naturally in an English sentence and EC2 rejects the
    # CreateSecurityGroup call outright, which terraform validate and plan both pass (rules.md F-1).
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.security_group_description))
    error_message = "security_group_description must be 1-255 characters from the set AWS accepts for a security group description: a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*. An apostrophe is NOT allowed - EC2 rejects CreateSecurityGroup with InvalidParameterValue, which otherwise only surfaces at apply time."
  }
}
variable "instance_name_prefix" {
  type        = string
  description = "Prefix the launch template and Auto Scaling group names are generated from. A prefix rather than a fixed name so that a replacement can be created before the old one is destroyed, and so two copies of this project do not collide"

  validation {
    condition     = can(regex("^[a-zA-Z0-9._-]{1,100}$", var.instance_name_prefix))
    error_message = "instance_name_prefix must be 1-100 characters of letters, digits, dots, underscores or hyphens, leaving room for the generated suffix inside the 255 character limit."
  }
}
variable "role_name_prefix" {
  type        = string
  description = "Prefix the container instance IAM role name is generated from, replacing the _monolithic template's fixed EcsAutoScalingGroupIamRole"

  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_-]{1,38}$", var.role_name_prefix))
    error_message = "role_name_prefix must be 1-38 characters from the IAM role name character set, leaving room for the generated suffix inside IAM's 64 character limit."
  }
}
variable "instance_profile_name_prefix" {
  type        = string
  description = "Prefix the instance profile name is generated from, replacing the _monolithic template's fixed EcsAutoScalingGroupProfile"

  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_-]{1,38}$", var.instance_profile_name_prefix))
    error_message = "instance_profile_name_prefix must be 1-38 characters from the IAM name character set, leaving room for the generated suffix inside IAM's 64 character limit."
  }
}
variable "iam_policy_arns" {
  type = list(string)
  default = [
    "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role",
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
  ]
  description = "Managed policies attached to the container instance role. Two, where the _monolithic template attached a different two - see the validation message for why one was dropped and one added"

  validation {
    condition     = alltrue([for arn in var.iam_policy_arns : can(regex("^arn:aws[a-zA-Z-]*:iam::", arn))])
    error_message = "iam_policy_arns must contain valid IAM policy ARNs."
  }
  validation {
    # AmazonEC2ContainerServiceforEC2Role is what RegisterContainerInstance, the agent's long poll and
    # the image pull are authorized by. Without it the instances launch, stay healthy, and never appear
    # in the cluster - which is the same symptom as the revoked egress rule and has to be ruled out the
    # same way.
    condition     = anytrue([for arn in var.iam_policy_arns : endswith(arn, "/AmazonEC2ContainerServiceforEC2Role")])
    error_message = "iam_policy_arns must include arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role. Without it the ECS agent cannot register the instance, and the only symptom is a cluster with no container instances in it."
  }
}
variable "ecs_config_options" {
  type        = map(string)
  default     = {}
  description = "Extra /etc/ecs/ecs.config lines beyond ECS_CLUSTER, as key-value pairs. Empty, which is what the _monolithic template wrote"

  validation {
    condition     = alltrue([for key in keys(var.ecs_config_options) : can(regex("^[A-Z][A-Z0-9_]*$", key))])
    error_message = "ecs_config_options keys must be upper-case agent variable names such as ECS_ENABLE_SPOT_INSTANCE_DRAINING."
  }
  validation {
    condition     = !contains(keys(var.ecs_config_options), "ECS_CLUSTER")
    error_message = "ecs_config_options must not contain ECS_CLUSTER, which is written from cluster_name. Setting it here would put two ECS_CLUSTER lines in the file and the agent reads the last one, so the cluster the instances join would stop matching the cluster the service is in."
  }
}
variable "instance_types" {
  type        = list(string)
  default     = ["t3.micro"]
  description = "Instance types the mixed instances policy may choose from, as overrides. One, as the _monolithic template had it"

  validation {
    condition     = length(var.instance_types) > 0
    error_message = "instance_types must contain at least one type. The launch template deliberately sets no instance_type, so the overrides are the only place a type is given."
  }
  validation {
    condition     = alltrue([for type in var.instance_types : can(regex("^[a-z0-9]+\\.[a-z0-9]+$", type))])
    error_message = "instance_types must contain valid EC2 instance types (e.g. t3.micro)."
  }
}
variable "min_size" {
  type        = number
  default     = 1
  description = "Minimum number of container instances"

  validation {
    condition     = var.min_size >= 0
    error_message = "min_size must be zero or greater."
  }
}
variable "max_size" {
  type        = number
  default     = 8
  description = "Maximum number of container instances. Eight, as the _monolithic template had it, and the headroom matters here: during a blue/green deployment both task sets run at once, so ECS asks for roughly double the steady-state capacity"

  validation {
    condition     = var.max_size >= var.min_size
    error_message = "max_size must be greater than or equal to min_size."
  }
}
variable "desired_capacity" {
  type        = number
  default     = 2
  description = "Starting number of container instances. The starting point only - managed scaling owns this field afterwards, which is why the resource ignores changes to it (rules.md E-8)"

  validation {
    condition     = var.desired_capacity >= var.min_size && var.desired_capacity <= var.max_size
    error_message = "desired_capacity must be between min_size and max_size."
  }
}
variable "default_cooldown" {
  type        = number
  default     = 0
  description = "Seconds after a scaling activity before another may start. Zero, as the _monolithic template had it, which leaves the pacing entirely to the capacity provider's instance warmup period"

  validation {
    condition     = var.default_cooldown >= 0
    error_message = "default_cooldown must be zero or greater."
  }
}
variable "on_demand_base_capacity" {
  type        = number
  default     = 0
  description = "Instances filled with on-demand capacity before the percentage split applies. Zero, as the _monolithic template had it, which with the percentage below makes the group entirely spot"

  validation {
    condition     = var.on_demand_base_capacity >= 0
    error_message = "on_demand_base_capacity must be zero or greater."
  }
}
variable "on_demand_percentage_above_base_capacity" {
  type        = number
  default     = 0
  description = "Percentage of capacity above the base filled on demand. Zero, so the whole group is spot - as the _monolithic template had it. Worth knowing when a task disappears without an ECS event explaining it: a reclaimed spot instance takes its tasks with it"

  validation {
    condition     = var.on_demand_percentage_above_base_capacity >= 0 && var.on_demand_percentage_above_base_capacity <= 100
    error_message = "on_demand_percentage_above_base_capacity must be between 0 and 100."
  }
}
variable "spot_allocation_strategy" {
  type        = string
  default     = "price-capacity-optimized"
  description = "How spot capacity is chosen across the instance types and zones"

  validation {
    condition     = contains(["lowest-price", "capacity-optimized", "capacity-optimized-prioritized", "price-capacity-optimized", "diversified"], var.spot_allocation_strategy)
    error_message = "spot_allocation_strategy must be one of lowest-price, capacity-optimized, capacity-optimized-prioritized, price-capacity-optimized or diversified."
  }
}
variable "protect_from_scale_in" {
  type        = bool
  default     = false
  description = "Whether instances are protected from scale-in. False, which is the half of the pair that managed_termination_protection DISABLED requires - ECS validates the two together"
}
variable "managed_draining" {
  type        = string
  default     = "ENABLED"
  description = "Whether ECS drains tasks off an instance that is terminating. Enabled, which is the provider default and what makes a spot reclamation on this all-spot group move tasks rather than kill them"

  validation {
    condition     = contains(["ENABLED", "DISABLED"], var.managed_draining)
    error_message = "managed_draining must be ENABLED or DISABLED."
  }
}
variable "managed_termination_protection" {
  type        = string
  default     = "DISABLED"
  description = "Whether ECS protects instances running tasks from scale-in, as the _monolithic template had it. Disabled, and paired with protect_from_scale_in false"

  validation {
    condition     = contains(["ENABLED", "DISABLED"], var.managed_termination_protection)
    error_message = "managed_termination_protection must be ENABLED or DISABLED. ENABLED additionally requires protect_from_scale_in to be true, and ECS rejects the mismatched pair."
  }
  validation {
    condition     = var.managed_termination_protection == "ENABLED" ? var.protect_from_scale_in : !var.protect_from_scale_in
    error_message = "managed_termination_protection and protect_from_scale_in must agree: ENABLED with protect_from_scale_in true, DISABLED with it false. ECS validates the pair at CreateCapacityProvider."
  }
}
variable "managed_scaling_status" {
  type        = string
  default     = "ENABLED"
  description = "Whether ECS adjusts the group's desired capacity from the tasks waiting to be placed, as the _monolithic template had it"

  validation {
    condition     = contains(["ENABLED", "DISABLED"], var.managed_scaling_status)
    error_message = "managed_scaling_status must be ENABLED or DISABLED."
  }
}
variable "managed_scaling_target_capacity" {
  type        = number
  default     = 100
  description = "Percentage of the group's capacity ECS aims to keep in use. A hundred, as the _monolithic template had it, which means no deliberate spare instance - during a deployment the second task set waits for capacity to be added"

  validation {
    condition     = var.managed_scaling_target_capacity >= 1 && var.managed_scaling_target_capacity <= 100
    error_message = "managed_scaling_target_capacity must be between 1 and 100."
  }
}
variable "managed_scaling_instance_warmup_period" {
  type        = number
  default     = 60
  description = "Seconds a new instance is given before it counts toward capacity, as the _monolithic template had it"

  validation {
    condition     = var.managed_scaling_instance_warmup_period >= 0 && var.managed_scaling_instance_warmup_period <= 10000
    error_message = "managed_scaling_instance_warmup_period must be between 0 and 10000 seconds."
  }
}
variable "default_strategy_base" {
  type        = number
  default     = 0
  description = "Tasks placed on this provider before the weighting applies, in the cluster's default strategy"

  validation {
    condition     = var.default_strategy_base >= 0
    error_message = "default_strategy_base must be zero or greater."
  }
}
variable "default_strategy_weight" {
  type        = number
  default     = 1
  description = "Relative share of tasks this provider takes in the cluster's default strategy. One provider, so any positive weight is the whole share"

  validation {
    condition     = var.default_strategy_weight >= 0
    error_message = "default_strategy_weight must be zero or greater. Zero would mean the cluster's default strategy places nothing on the only provider it has."
  }
}
variable "ssh_port" {
  type        = number
  default     = 22
  description = "Port the SSH rule from the bastion opens"

  validation {
    condition     = var.ssh_port >= 1 && var.ssh_port <= 65535
    error_message = "ssh_port must be between 1 and 65535."
  }
}
variable "ssh_ingress_source_security_groups" {
  type        = map(string)
  default     = {}
  description = "Groups allowed to reach the container instances on the SSH port, keyed by a caller-chosen label. A map rather than a list because the bastion's group ID is another module's output, unknown until apply, and for_each needs statically known keys (rules.md B-8)"

  validation {
    condition     = alltrue([for label in keys(var.ssh_ingress_source_security_groups) : can(regex("^[a-zA-Z0-9._-]+$", label))])
    error_message = "ssh_ingress_source_security_groups keys are labels used in the rule descriptions and resource addresses, so each must be a non-empty string of letters, digits, dots, underscores or hyphens."
  }
  validation {
    condition     = alltrue([for id in values(var.ssh_ingress_source_security_groups) : can(regex("^sg-[0-9a-f]+$", id))])
    error_message = "ssh_ingress_source_security_groups must contain valid security group IDs (e.g. sg-0123456789abcdef0)."
  }
}
variable "ingress_source_security_groups" {
  type        = map(string)
  default     = {}
  description = "Groups allowed to reach the container instances on any port, keyed by a caller-chosen label. Empty: with awsvpc networking nothing in this project is in that path, because the load balancer connects to the task's own interface rather than to the instance (rules.md B-8)"

  validation {
    condition     = alltrue([for label in keys(var.ingress_source_security_groups) : can(regex("^[a-zA-Z0-9._-]+$", label))])
    error_message = "ingress_source_security_groups keys are labels used in the rule descriptions and resource addresses, so each must be a non-empty string of letters, digits, dots, underscores or hyphens."
  }
  validation {
    condition     = alltrue([for id in values(var.ingress_source_security_groups) : can(regex("^sg-[0-9a-f]+$", id))])
    error_message = "ingress_source_security_groups must contain valid security group IDs (e.g. sg-0123456789abcdef0)."
  }
}
