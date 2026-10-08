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

    It has to be an ECS-optimized image, and an arm64 one. ECS-optimized because the ECS agent and the
    /etc/ecs/ecs.config convention the launch template userdata relies on come from the AMI, not from
    anything here - a plain Amazon Linux image launches successfully, has no agent, and so never joins the
    cluster. arm64 to match both the instance family and the image the builder pushes.
  DESC

  validation {
    condition     = can(regex("^ami-[0-9a-f]+$", var.ami_id))
    error_message = "ami_id must be a valid AMI ID (e.g. ami-0123456789abcdef0)."
  }
}
variable "instance_types" {
  type        = list(string)
  default     = ["r8g.2xlarge", "r7g.2xlarge", "r6g.2xlarge", "m8g.2xlarge", "m7g.2xlarge", "m6g.2xlarge"]
  description = <<-DESC
    Instance types offered to the mixed instances policy as overrides. The order is a preference only
    under capacity-optimized-prioritized; price-capacity-optimized, the default here, weighs every listed
    pool on price and capacity alike.

    The _monolithic template offered ["r8g.2xlarge"] alone: 8 vCPU and 64 GiB per instance, against a
    task asking for 2048 CPU units and 15360 MiB. It is still first, and the other five are the same
    shape from the neighbouring Graviton generations - 8 vCPU each, 64 GiB for r and 32 GiB for m, both
    of which hold the task with room for the agent.

    Widened because the group runs entirely on spot - see on_demand_percentage_above_base_capacity - and
    a single type on spot is a single capacity pool per zone. In ap-northeast-1 that pool was too
    shallow to hold four instances: the a zone answered every request with UnfulfillableCapacity, and six
    of the first ten instances in the c zone were reclaimed within 25 minutes, each taking a task with
    it. get-spot-placement-scores rated r8g.2xlarge alone 1 out of 10 in both zones for four instances,
    and these six together 9. To reproduce the original exactly, pass ["r8g.2xlarge"] - and expect the
    shortfall to show only in the group's scaling activities, with the cluster short of container
    instances and tasks left PENDING.

    Compare the demo's dd figures with the instance type each task landed on (the container instance's
    ecs.instance-type attribute). Measured here, the direct-I/O writes ran at a median of about 320 MB/s
    on both r7g.2xlarge and m8g.2xlarge, above the gp3 volume's provisioned 125 MiB/s - so the volume is
    not obviously the ceiling, and the types' EBS bandwidth may be. That baseline is 312.5 MB/s for the 7g
    and 8g types here and 296.875 MB/s for r6g and m6g, which were not measured.

    Types have to be arm64 to match the AMI and the pushed image, and large enough for one task - a type
    with less memory than task_memory leaves the service unable to place anything, reported as
    "was unable to place a task because no container instance met all of its requirements".
  DESC

  validation {
    condition     = length(var.instance_types) >= 1
    error_message = "instance_types must contain at least one instance type."
  }

  validation {
    condition     = alltrue([for type in var.instance_types : can(regex("^[a-z0-9]+[a-z0-9-]*\\.[a-z0-9]+$", type))])
    error_message = "instance_types entries must be valid EC2 instance types (e.g. r8g.2xlarge)."
  }

  validation {
    # Same Graviton shape check as the image builder's instance_type, and for the paired reason: the image
    # these instances pull is built arm64, and an x86 container instance pulling it stops the task with
    # "image Manifest does not contain descriptor matching platform linux/amd64" after the instance has
    # registered perfectly normally.
    condition     = alltrue([for type in var.instance_types : can(regex("^[a-z]+[0-9]+g[a-z]*\\.", type))])
    error_message = "instance_types entries must be Graviton (arm64) families such as r8g.2xlarge, because the image the builder pushes is arm64. To run x86 container instances, the builder has to produce a multi-architecture manifest instead."
  }
}
variable "min_size" {
  type        = number
  default     = 4
  description = "Minimum container instances, as the _monolithic template had it"

  validation {
    condition     = var.min_size >= 0
    error_message = "min_size must be zero or greater."
  }
}
variable "max_size" {
  type        = number
  default     = 8
  description = "Maximum container instances, as the _monolithic template had it. This is the ceiling managed scaling is allowed to reach; with target_capacity at 100 it is only reached if tasks are asking for it"

  validation {
    condition     = var.max_size >= 1
    error_message = "max_size must be at least 1."
  }

  validation {
    condition     = var.max_size >= var.min_size
    error_message = "max_size must be greater than or equal to min_size. The Auto Scaling group API rejects the reverse at apply time with a ValidationError."
  }
}
variable "desired_capacity" {
  type        = number
  default     = 4
  description = <<-DESC
    Container instances launched up front, as the _monolithic template had it.

    Four instances for two tasks is more than the workload needs, and it is what makes the service's
    second placement strategy - spread over instanceId - do something visible: with host networking and a
    bind mount, two tasks on one instance would write into the same host directory.
  DESC

  validation {
    condition     = var.desired_capacity >= 0
    error_message = "desired_capacity must be zero or greater."
  }

  validation {
    condition     = var.desired_capacity >= var.min_size && var.desired_capacity <= var.max_size
    error_message = "desired_capacity must be between min_size and max_size inclusive, which the Auto Scaling group API also enforces at apply time."
  }
}
variable "default_cooldown" {
  type        = number
  default     = 0
  description = "Seconds the group waits after a scaling activity before starting another, as the _monolithic template had it. Zero because ECS managed scaling does the deciding here - a cooldown on the group would delay the capacity provider's own scaling actions and make the group look unresponsive rather than busy"

  validation {
    condition     = var.default_cooldown >= 0
    error_message = "default_cooldown must be zero or greater."
  }
}
variable "on_demand_base_capacity" {
  type        = number
  default     = 0
  description = "How many of the first instances are on demand regardless of the percentage below, as the _monolithic template had it. Zero means the group is entirely spot"

  validation {
    condition     = var.on_demand_base_capacity >= 0
    error_message = "on_demand_base_capacity must be zero or greater."
  }
}
variable "on_demand_percentage_above_base_capacity" {
  type        = number
  default     = 0
  description = <<-DESC
    Percentage of capacity above the base that is on demand. Zero - entirely spot - as the
    _monolithic template had it.

    Worth knowing what that means for the demo rather than just for the bill. A spot instance can be
    reclaimed with two minutes of notice, and nothing here handles that notice: there is no capacity
    provider draining hook and no instance lifecycle hook, so a reclaimed instance takes its task with it
    and the service replaces it elsewhere. For a test that writes files to a host volume, that is a host
    volume that disappears - which is a fair illustration of what a bind mount is, and a thing to
    understand before reading anything into a gap in the output.
  DESC

  validation {
    condition     = var.on_demand_percentage_above_base_capacity >= 0 && var.on_demand_percentage_above_base_capacity <= 100
    error_message = "on_demand_percentage_above_base_capacity must be between 0 and 100."
  }
}
variable "spot_allocation_strategy" {
  type        = string
  default     = "price-capacity-optimized"
  description = "How spot capacity is chosen across the pools, as the _monolithic template had it. price-capacity-optimized weighs the chance of interruption as well as the price, which for a group that is 100 percent spot is the one that keeps instances alive longest"

  validation {
    condition     = contains(["lowest-price", "capacity-optimized", "capacity-optimized-prioritized", "price-capacity-optimized"], var.spot_allocation_strategy)
    error_message = "spot_allocation_strategy must be one of lowest-price, capacity-optimized, capacity-optimized-prioritized, price-capacity-optimized."
  }
}
variable "capacity_provider_name" {
  type        = string
  default     = "ecs-volumes-capacity-provider"
  description = <<-DESC
    Name of the capacity provider. The _monolithic template used the literal "CapacityProvider", which
    makes a second copy of this project in one account fail - so the caller derives it from the project
    name instead.

    This name cannot be changed in place. ECS has no API to repoint a capacity provider at a different
    Auto Scaling group or to rename one, so the provider marks the whole resource as needing replacement,
    and the replacement is refused while the cluster or a service still names it.
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
  description = "Whether ECS manages the group's capacity, as the _monolithic template had it. ENABLED hands the group's desired count to ECS, which sizes it from the tasks waiting to be placed; DISABLED leaves desired_capacity as written and the service then cannot grow past it"

  validation {
    condition     = contains(["ENABLED", "DISABLED"], var.managed_scaling_status)
    error_message = "managed_scaling_status must be ENABLED or DISABLED."
  }
}
variable "managed_scaling_target_capacity" {
  type        = number
  default     = 100
  description = "Target percentage of the group's capacity that ECS aims to keep in use, as the _monolithic template had it. 100 packs instances fully before adding one, which is the right end of the trade for a fixed workload and the wrong end if tasks need somewhere to go immediately"

  validation {
    condition     = var.managed_scaling_target_capacity >= 1 && var.managed_scaling_target_capacity <= 100
    error_message = "managed_scaling_target_capacity must be between 1 and 100."
  }
}
variable "managed_scaling_instance_warmup_period" {
  type        = number
  default     = 30
  description = "Seconds ECS waits before counting a newly launched instance towards the metric, as the _monolithic template had it. Too short and ECS double-counts a booting instance as available capacity and under-provisions; the ECS-optimized AMI needs roughly this long to have the agent registered"

  validation {
    condition     = var.managed_scaling_instance_warmup_period >= 0
    error_message = "managed_scaling_instance_warmup_period must be zero or greater."
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

    The consequence of DISABLED is that a scale-in can terminate an instance that is running a task. For a
    group that is already entirely spot, and therefore already losing instances without warning, this
    changes little.
  DESC

  validation {
    condition     = contains(["ENABLED", "DISABLED"], var.managed_termination_protection)
    error_message = "managed_termination_protection must be ENABLED or DISABLED."
  }

  validation {
    # Cross-variable condition, available since Terraform 1.9. The constraint is about the pair: ECS
    # rejects managed termination protection on a group that does not have scale-in protection with
    # "The managed termination protection setting for the capacity provider is invalid", and managed
    # termination protection additionally requires managed scaling to be enabled.
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
  description = <<-DESC
    Whether ECS drains tasks off an instance that is going away. ENABLED, which is the ECS default for a
    new capacity provider and which the _monolithic template left unstated.

    Stated explicitly because it is what handles a spot reclamation: ECS notices the interruption notice,
    stops the task gracefully and starts a replacement, instead of the task disappearing with the
    instance. On a group that is 100 percent spot this is the difference between an interruption being a
    brief gap and being a hard kill.
  DESC

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
  default     = "container-instance"
  description = "Name tag applied to the launched instances, as the _monolithic template had it. Also the prefix of the launch template's and the Auto Scaling group's generated names, which is why its character set is narrower than a tag's would otherwise need to be"

  validation {
    condition     = length(var.instance_name) > 0
    error_message = "instance_name must not be empty."
  }

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
  default     = "container-instance-sg"
  description = "Name of the container instance security group, as the _monolithic template had it"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.security_group_name)) && !startswith(var.security_group_name, "sg-")
    error_message = "security_group_name must be 1-255 characters from the set AWS accepts for a security group name (a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*, no apostrophe) and must not start with \"sg-\", which EC2 reserves for security group IDs."
  }
}
variable "security_group_description" {
  type        = string
  default     = "Security group for the ECS container instances"
  description = "Description attached to the security group. The _monolithic template had \"Security Group for ASG\". Changing it replaces the group, and replacing it means replacing every instance the launch template has launched, because AWS has no API to modify a security group description (rules.md F-1)"

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
    label. Empty creates no ingress rule, which is what the _monolithic template's group had.

    A map rather than a list because these IDs are another module's output and therefore unknown until
    apply, and for_each needs statically known keys - a list fed through toset fails the plan with
    "Invalid for_each argument ... cannot be determined until apply" (rules.md B-8).

    The key appears in the rule description, so it is what makes a rule's origin readable in a plan.
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
    "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceAutoscaleRole",
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  ]
  description = <<-DESC
    Managed policy ARNs attached to the container instance role, which are the two the _monolithic
    template attached as separate attachment resources.

    AmazonEC2ContainerServiceforEC2Role is the one that has to be here: it carries
    RegisterContainerInstance, Poll, SubmitTaskStateChange and the ECR pull permissions, so without it the
    agent cannot join the cluster and the instance is simply absent rather than broken.

    AmazonEC2ContainerServiceAutoscaleRole is kept for fidelity with the original and does nothing on an
    instance role. It is the service role policy for Application Auto Scaling to change an ECS service's
    desired count, with a trust relationship for application-autoscaling.amazonaws.com; attached to a role
    that ec2.amazonaws.com assumes, nothing ever uses it. Dropping it from this list would be the right
    narrowing and would be a change to what the original did.
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

    This is the ECS equivalent of the Add-on configuration_values pattern (rules.md E-5): agent behaviour
    belongs in configuration rather than in a command run against a live instance. ECS_IMAGE_PULL_BEHAVIOR
    and ECS_ENGINE_TASK_CLEANUP_WAIT_DURATION are the two worth knowing about for a demo that pushes over
    one moving tag and writes large files.

    Every value is written verbatim, so a value needing quotes in that file has to arrive with them.
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
  default     = 100
  description = <<-DESC
    Root volume size in GiB for the container instances. The _monolithic template left this unset, taking
    the ECS-optimized AMI's own 30 GiB.

    Raised, and this is the one place where this project's subject and its sizing meet. The task
    bind-mounts a host directory and writes large files into it in a loop, so those files land on this
    volume. With the defaults - 200 MiB a file, five files kept - a single task needs about a gigabyte,
    which 30 GiB covers; raising write_size_mb or retained_file_count, or placing two tasks on one
    instance, does not. Running it out of space does not stop the task: the agent reports the instance as
    low on disk, the dd inside the container starts failing, and the loop carries on printing.
  DESC

  validation {
    condition     = var.root_volume_size >= 30
    error_message = "root_volume_size must be at least 30 GiB, which is the ECS-optimized AMI's own root volume size."
  }
}
variable "root_volume_type" {
  type        = string
  default     = "gp3"
  description = "Root volume type for the container instances. gp3 rather than the AMI's default gp2, because the demo measures write throughput to this volume with direct I/O and gp2's throughput is tied to its size while gp3's is not - on gp2 the numbers would say more about the volume size than about anything else"

  validation {
    condition     = contains(["gp2", "gp3", "io1", "io2"], var.root_volume_type)
    error_message = "root_volume_type must be one of gp2, gp3, io1, io2."
  }
}
variable "host_volume_path" {
  type        = string
  default     = "/ecs/test"
  description = "Host directory the task bind-mounts, created by the launch template userdata. The caller passes the same value here and to the task definition, so they cannot disagree (rules.md B-5). Docker creates a missing bind-mount source itself, so a mismatch is not an error - it is an empty directory at the path being inspected while the writes go somewhere else"

  validation {
    condition     = can(regex("^/[^\\s]+$", var.host_volume_path))
    error_message = "host_volume_path must be an absolute path with no whitespace."
  }
}
variable "default_strategy_base" {
  type        = number
  default     = 0
  description = "Tasks placed on this provider before the weights are applied, in the cluster's default strategy. Zero, as the _monolithic template had it, which with a single provider means the weight decides everything - base only matters when a second provider exists to split against"

  validation {
    condition     = var.default_strategy_base >= 0
    error_message = "default_strategy_base must be zero or greater."
  }
}
variable "default_strategy_weight" {
  type        = number
  default     = 1
  description = "Relative share of tasks this provider takes in the cluster's default strategy, as the _monolithic template had it. Any positive number behaves identically while this is the only provider; zero would mean the default strategy places nothing, and a task run without a strategy of its own would then fail to launch"

  validation {
    condition     = var.default_strategy_weight >= 0
    error_message = "default_strategy_weight must be zero or greater."
  }
}
variable "root_device_name" {
  type        = string
  default     = "/dev/xvda"
  description = <<-DESC
    Device name of the AMI's root volume, which the launch template's block device mapping has to name to
    resize it. /dev/xvda is the Amazon Linux 2023 root device, and the ECS-optimized AMI this module takes
    is built on it.

    A variable rather than a literal because it is coupled to ami_id and nothing enforces that. A mapping
    naming a device the AMI does not actually have is not an error: EC2 accepts it and attaches a second,
    unformatted, unmounted volume. The result is a container instance whose root volume is still at the
    AMI's own size, paying for an extra volume that nothing uses - and the symptom is the disk filling up
    while the console shows plenty of storage attached.
  DESC

  validation {
    condition     = can(regex("^/dev/[a-z0-9/]+$", var.root_device_name))
    error_message = "root_device_name must be a device path such as /dev/xvda or /dev/sda1."
  }
}
