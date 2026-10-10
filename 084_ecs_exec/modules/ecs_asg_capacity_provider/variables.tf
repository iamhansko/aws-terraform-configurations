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
  description = <<-DESC
    Subnets the Auto Scaling group spans. Private subnets with a default route to a NAT gateway, as the
    _monolithic template had it.

    "With a default route" is not optional and is not something this module can check. A container
    instance that cannot reach ecs.<region>.amazonaws.com never calls RegisterContainerInstance, so it
    never appears in the cluster at all - and an instance that never registers produces no ECS event, no
    failed task and no error. The cluster simply reports fewer registered instances than the group has
    launched.
  DESC

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
    error_message = "cluster_name must be 1-255 characters of letters, digits, underscores and hyphens."
  }
}
variable "ami_id" {
  type        = string
  description = <<-DESC
    AMI for the container instances, resolved by the caller from an SSM public parameter and passed in as
    an id (rules.md B-6).

    It has to be an ECS-optimized image of the same architecture as instance_type. ECS-optimized because
    the ECS agent and the /etc/ecs/ecs.config convention the launch template userdata relies on come from
    the AMI, not from anything here - a plain Amazon Linux image launches successfully, has no agent, and so
    never joins the cluster.
  DESC

  validation {
    condition     = can(regex("^ami-[0-9a-f]+$", var.ami_id))
    error_message = "ami_id must be a valid AMI ID (e.g. ami-0123456789abcdef0)."
  }
}
variable "instance_type" {
  type        = string
  default     = "t3.medium"
  description = <<-DESC
    Instance type of the container instances, as the _monolithic template had it.

    With awsvpc tasks the number that runs out first on this type is not CPU or memory but network
    interfaces. A t3.medium takes three ENIs, one of which is the instance's own, so it holds two awsvpc
    tasks however small they are. ECS managed scaling counts ENIs when it sizes the group, so a third task
    makes the group grow rather than wait - but it is why a cluster of two t3.medium instances is full at
    four tasks.
  DESC

  validation {
    condition     = can(regex("^[a-z0-9]+[a-z0-9-]*\\.[a-z0-9]+$", var.instance_type))
    error_message = "instance_type must be a valid EC2 instance type (e.g. t3.medium)."
  }
}
variable "min_size" {
  type        = number
  default     = 1
  description = "Minimum container instances, as the _monolithic template had it"

  validation {
    condition     = var.min_size >= 0 && floor(var.min_size) == var.min_size
    error_message = "min_size must be a whole number, zero or greater."
  }
}
variable "max_size" {
  type        = number
  default     = 6
  description = "Maximum container instances, as the _monolithic template had it. This is the ceiling managed scaling is allowed to reach; with target_capacity at 100 it is only reached if tasks are asking for it"

  validation {
    condition     = var.max_size >= 1 && floor(var.max_size) == var.max_size
    error_message = "max_size must be a whole number of at least 1."
  }

  validation {
    condition     = var.max_size >= var.min_size
    error_message = "max_size must be greater than or equal to min_size. The Auto Scaling group API rejects the reverse at apply time with a ValidationError."
  }
}
variable "desired_capacity" {
  type        = number
  default     = 2
  description = "Container instances launched up front, as the _monolithic template had it. Only the starting point: ECS managed scaling owns the field afterwards, which is why the group ignores changes to it (see main.tf)"

  validation {
    condition     = var.desired_capacity >= 0 && floor(var.desired_capacity) == var.desired_capacity
    error_message = "desired_capacity must be a whole number, zero or greater."
  }

  validation {
    condition     = var.desired_capacity >= var.min_size && var.desired_capacity <= var.max_size
    error_message = "desired_capacity must be between min_size and max_size inclusive, which the Auto Scaling group API also enforces at apply time."
  }
}
variable "default_cooldown" {
  type        = number
  default     = null
  description = "Seconds the group waits after a scaling activity before starting another. Null leaves the Auto Scaling default of 300, which is what the _monolithic template had by not setting it. Managed scaling drives this group through target tracking, which does not wait on the cooldown"

  validation {
    condition     = var.default_cooldown == null || try(var.default_cooldown >= 0, false)
    error_message = "default_cooldown must be zero or greater, or null for the Auto Scaling default."
  }
}
variable "capacity_distribution_strategy" {
  type        = string
  default     = "balanced-only"
  description = "How the group spreads instances across zones, as the _monolithic template had it. balanced-only waits for capacity in the zone it is balancing towards; balanced-best-effort launches in another zone instead"

  validation {
    condition     = contains(["balanced-only", "balanced-best-effort"], var.capacity_distribution_strategy)
    error_message = "capacity_distribution_strategy must be balanced-only or balanced-best-effort."
  }
}
variable "capacity_provider_name" {
  type        = string
  description = <<-DESC
    Name of the capacity provider. No default: CloudFormation generated this name and Terraform requires
    one, so the caller derives it from the project name.

    This name cannot be changed in place. ECS has no API to rename a capacity provider, so the provider
    marks the whole resource as needing replacement, and the replacement is refused while the cluster or a
    service still names it.
  DESC

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9_-]{0,254}$", var.capacity_provider_name))
    error_message = "capacity_provider_name must be 1-255 characters of letters, digits, underscores and hyphens, starting with a letter or digit."
  }

  validation {
    # A real ECS constraint that only shows up at apply time, as InvalidParameterException with the text
    # "The capacity provider name cannot be prefixed with aws, ecs, or fargate".
    condition     = !can(regex("^(?i)(aws|ecs|fargate)", var.capacity_provider_name))
    error_message = "capacity_provider_name must not start with aws, ecs or fargate in any casing, which ECS reserves and rejects at apply time with InvalidParameterException."
  }
}
variable "managed_scaling_status" {
  type        = string
  default     = "ENABLED"
  description = "Whether ECS manages the group's capacity, as the _monolithic template had it. ENABLED hands the group's desired count to ECS, which sizes it from the tasks waiting to be placed; DISABLED leaves desired_capacity as written and the services then cannot grow past it"

  validation {
    condition     = contains(["ENABLED", "DISABLED"], var.managed_scaling_status)
    error_message = "managed_scaling_status must be ENABLED or DISABLED."
  }
}
variable "managed_scaling_target_capacity" {
  type        = number
  default     = 100
  description = "Target percentage of the group's capacity that ECS aims to keep in use, as the _monolithic template had it. 100 packs instances fully before adding one"

  validation {
    condition     = var.managed_scaling_target_capacity >= 1 && var.managed_scaling_target_capacity <= 100
    error_message = "managed_scaling_target_capacity must be between 1 and 100."
  }
}
variable "managed_scaling_instance_warmup_period" {
  type        = number
  default     = 30
  description = "Seconds ECS waits before counting a newly launched instance towards the metric, as the _monolithic template had it"

  validation {
    condition     = var.managed_scaling_instance_warmup_period >= 0 && var.managed_scaling_instance_warmup_period <= 10000
    error_message = "managed_scaling_instance_warmup_period must be between 0 and 10000 seconds."
  }
}
variable "managed_scaling_minimum_step_size" {
  type        = number
  default     = 1
  description = "Fewest instances one managed scale-out may add, as the _monolithic template set it"

  validation {
    condition     = var.managed_scaling_minimum_step_size >= 1 && var.managed_scaling_minimum_step_size <= 10000
    error_message = "managed_scaling_minimum_step_size must be between 1 and 10000."
  }
}
variable "managed_scaling_maximum_step_size" {
  type        = number
  default     = 10000
  description = "Most instances one managed scale-out may add, as the _monolithic template set it. 10000 is the API maximum, so in practice the ceiling is max_size"

  validation {
    condition     = var.managed_scaling_maximum_step_size >= 1 && var.managed_scaling_maximum_step_size <= 10000
    error_message = "managed_scaling_maximum_step_size must be between 1 and 10000."
  }

  validation {
    condition     = var.managed_scaling_maximum_step_size >= var.managed_scaling_minimum_step_size
    error_message = "managed_scaling_maximum_step_size must be at least managed_scaling_minimum_step_size, which ECS otherwise rejects at apply time."
  }
}
variable "managed_termination_protection" {
  type        = string
  default     = "DISABLED"
  description = <<-DESC
    Whether ECS protects instances running tasks from scale-in, as the _monolithic template had it.

    DISABLED, and it has to stay consistent with the group. Enabling it requires the Auto Scaling group to
    have instance scale-in protection on as well - the ECS API rejects the capacity provider outright
    otherwise - so this and protect_from_scale_in are a pair rather than two settings, which is what the
    cross-variable validation below enforces.
  DESC

  validation {
    condition     = contains(["ENABLED", "DISABLED"], var.managed_termination_protection)
    error_message = "managed_termination_protection must be ENABLED or DISABLED."
  }

  validation {
    # Cross-variable condition, available since Terraform 1.9. ECS rejects managed termination protection
    # on a group that does not have scale-in protection, and it additionally requires managed scaling.
    condition     = var.managed_termination_protection == "DISABLED" || (var.protect_from_scale_in && var.managed_scaling_status == "ENABLED")
    error_message = "managed_termination_protection may only be ENABLED when protect_from_scale_in is true and managed_scaling_status is ENABLED. ECS rejects the other combinations at apply time, after the Auto Scaling group has already been created."
  }
}
variable "protect_from_scale_in" {
  type        = bool
  default     = false
  description = "Whether the Auto Scaling group marks new instances as protected from scale-in. False, as the _monolithic template had it. This is the group-side half of managed_termination_protection and the two are validated together"
}
variable "managed_draining" {
  type        = string
  default     = "ENABLED"
  description = "Whether ECS drains tasks off an instance that is going away, as the _monolithic template had it. With it, a scale-in stops the instance only after its tasks have been replaced elsewhere"

  validation {
    condition     = contains(["ENABLED", "DISABLED"], var.managed_draining)
    error_message = "managed_draining must be ENABLED or DISABLED."
  }
}
variable "key_name" {
  type        = string
  default     = null
  description = "Name of the EC2 key pair attached to the container instances, as the _monolithic template had it. Null attaches none. No port is open to these instances and they have no public address, so this is a fallback for when the SSM agent is what is broken"

  validation {
    condition     = var.key_name == null || can(regex("^[ -~]{1,255}$", var.key_name))
    error_message = "key_name must be 1-255 printable ASCII characters, or null to attach no key pair."
  }
}
variable "instance_name" {
  type        = string
  default     = "ecs-container-instance"
  description = "Name tag applied to the launched instances, as the _monolithic template had it. Also the prefix of the launch template's and the Auto Scaling group's generated names, which is why its character set is narrower than a tag's would otherwise need to be"

  validation {
    # Launch template names accept letters, digits and ( ) . / _ - only, and a space or another character
    # outside that set is rejected at apply time with a ValidationError naming the launch template rather
    # than this variable.
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9._-]{0,99}$", var.instance_name))
    error_message = "instance_name must be 1-100 characters of letters, digits, dots, underscores and hyphens, starting with a letter or digit, because it is also used as the launch template and Auto Scaling group name prefix."
  }
}
variable "security_group_name" {
  type        = string
  default     = "ecs-container-instance-sg"
  description = "Name of the container instance security group, as the _monolithic template had it"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.security_group_name)) && !startswith(var.security_group_name, "sg-")
    error_message = "security_group_name must be 1-255 characters from the set AWS accepts for a security group name (a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*, no apostrophe) and must not start with \"sg-\", which EC2 reserves for security group IDs."
  }
}
variable "security_group_description" {
  type        = string
  default     = "Security group for the ECS container instances"
  description = "Description attached to the security group. The _monolithic template had \"Security Group\". Changing it replaces the group, and replacing it means replacing every instance the launch template has launched, because AWS has no API to modify a security group description (rules.md F-1)"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.security_group_description))
    error_message = "security_group_description must be 1-255 characters from the set AWS accepts for a security group description: a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*. An apostrophe is NOT allowed - EC2 rejects the CreateSecurityGroup call with InvalidParameterValue, which otherwise only surfaces at apply time (rules.md F-1)."
  }
}
variable "ingress_source_security_groups" {
  type        = map(string)
  default     = {}
  description = <<-DESC
    Security group IDs allowed all inbound traffic to the container instances, keyed by a caller-chosen
    label. Empty creates no ingress rule, which is right while the tasks use awsvpc networking - see main.tf
    for what the _monolithic template admitted here and why it matched nothing.

    A map rather than a list because these IDs are another module's output and therefore unknown until
    apply, and for_each needs statically known keys (rules.md B-8). The key appears in the rule
    description, so it is what makes a rule's origin readable in a plan.
  DESC

  validation {
    condition     = alltrue([for label in keys(var.ingress_source_security_groups) : can(regex("^[a-zA-Z0-9._-]+$", label))])
    error_message = "ingress_source_security_groups keys are labels used in the rule descriptions, so each must be a non-empty string of letters, digits, dots, underscores or hyphens - the character set AWS accepts in a security group rule description (rules.md F-1)."
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
    Managed policy ARNs attached to the container instance role, which are the two the _monolithic
    template attached as separate numbered attachment resources.

    AmazonEC2ContainerServiceforEC2Role is the one that has to be here: it carries
    RegisterContainerInstance, Poll, SubmitTaskStateChange and the ECR pull permissions, so without it the
    agent cannot join the cluster and the instance is simply absent rather than broken.
    AmazonSSMManagedInstanceCore makes the instances reachable with Session Manager, which is the way in
    when the agent is what is broken - nothing opens a port to them.

    Neither of these is what ECS Exec uses. An exec session runs as the task role, from inside the task.
  DESC

  validation {
    condition     = length(var.iam_policy_arns) > 0 && alltrue([for arn in var.iam_policy_arns : can(regex("^arn:aws[a-z-]*:iam::", arn))])
    error_message = "iam_policy_arns must be a non-empty list of IAM policy ARNs."
  }
}
variable "ecs_config_options" {
  type        = map(string)
  default     = {}
  description = <<-DESC
    Extra key/value pairs written into /etc/ecs/ecs.config alongside ECS_CLUSTER, which is the file the
    ECS agent reads at startup. Empty reproduces the _monolithic template, which wrote only the cluster
    name.

    Agent behaviour belongs in configuration rather than in a command run against a live instance, the ECS
    counterpart of rules.md E-5. Every value is written verbatim, so a value needing quotes in that file has
    to arrive with them.
  DESC

  validation {
    condition     = alltrue([for key in keys(var.ecs_config_options) : can(regex("^ECS_[A-Z0-9_]+$", key))])
    error_message = "ecs_config_options keys must be ECS agent variable names, e.g. ECS_IMAGE_PULL_BEHAVIOR."
  }

  validation {
    # The file is one key=value per line, so a newline in a value produces a line the agent reads as a
    # malformed directive - and the agent's response to a malformed config is to fall back to defaults
    # silently rather than to refuse to start.
    condition     = alltrue([for value in values(var.ecs_config_options) : !can(regex("[\n\r]", value))])
    error_message = "ecs_config_options values must not contain newlines, because each pair is written as a single key=value line in /etc/ecs/ecs.config."
  }
}
variable "root_volume_size" {
  type        = number
  default     = null
  description = "Root volume size in GiB for the container instances. Null declares no block device mapping, which is what the _monolithic template had: the ECS-optimized AMI's own 30 GiB root volume"

  validation {
    condition     = var.root_volume_size == null || try(var.root_volume_size >= 30, false)
    error_message = "root_volume_size must be at least 30 GiB, which is the ECS-optimized AMI's own root volume size, or null to keep the AMI's volume."
  }
}
variable "root_volume_type" {
  type        = string
  default     = "gp3"
  description = "Root volume type, used only when root_volume_size is set"

  validation {
    condition     = contains(["gp2", "gp3", "io1", "io2"], var.root_volume_type)
    error_message = "root_volume_type must be one of gp2, gp3, io1, io2."
  }
}
variable "root_device_name" {
  type        = string
  default     = "/dev/xvda"
  description = <<-DESC
    Device name of the AMI's root volume, used only when root_volume_size is set. /dev/xvda is the Amazon
    Linux 2023 root device, and the ECS-optimized AMI this module takes is built on it.

    Coupled to ami_id and nothing enforces that: a mapping naming a device the AMI does not have is not an
    error. EC2 attaches a second, unformatted volume and the root volume stays at the AMI's own size.
  DESC

  validation {
    condition     = can(regex("^/dev/[a-z0-9/]+$", var.root_device_name))
    error_message = "root_device_name must be a device path such as /dev/xvda or /dev/sda1."
  }
}
variable "additional_cluster_capacity_providers" {
  type        = list(string)
  default     = []
  description = "Capacity providers associated with the cluster besides this module's own, such as FARGATE and FARGATE_SPOT. Associating them does not place anything on them; the default strategy below still names only this provider"

  validation {
    condition     = alltrue([for name in var.additional_cluster_capacity_providers : can(regex("^[a-zA-Z0-9][a-zA-Z0-9_-]{0,254}$", name))])
    error_message = "additional_cluster_capacity_providers entries must be capacity provider names, e.g. FARGATE or FARGATE_SPOT."
  }
}
variable "default_strategy_base" {
  type        = number
  default     = 0
  description = "Tasks placed on this provider before the weights are applied, in the cluster's default strategy, as the _monolithic template had it"

  validation {
    condition     = var.default_strategy_base >= 0 && var.default_strategy_base <= 100000
    error_message = "default_strategy_base must be between 0 and 100000."
  }
}
variable "default_strategy_weight" {
  type        = number
  default     = 100
  description = "Relative share of tasks this provider takes in the cluster's default strategy, as the _monolithic template had it. Any positive number behaves identically while this is the only provider in the strategy; zero would mean a task run without a strategy of its own fails to launch"

  validation {
    condition     = var.default_strategy_weight >= 0 && var.default_strategy_weight <= 1000
    error_message = "default_strategy_weight must be between 0 and 1000."
  }
}
