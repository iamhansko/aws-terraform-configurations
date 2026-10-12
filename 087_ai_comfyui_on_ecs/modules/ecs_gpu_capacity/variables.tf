variable "name" {
  type        = string
  description = "Prefix of the Auto Scaling group, the launch template, the scaling resources and the instance role, and the instances' Name tag"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,40}$", var.name))
    error_message = "name must be 2-41 characters of lowercase letters, digits and hyphens."
  }
}
variable "region" {
  type        = string
  description = "Region the instances run in, which the REX-Ray plugin is told so it creates and attaches volumes there"

  validation {
    condition     = can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]$", var.region))
    error_message = "region must be an AWS region name such as ap-northeast-2."
  }
}
variable "cluster_name" {
  type        = string
  description = "ECS cluster the instances join, written into their ecs.config"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,255}$", var.cluster_name))
    error_message = "cluster_name must be a valid ECS cluster name."
  }
}
variable "cluster_arn" {
  type        = string
  description = "ARN of that cluster, which the ECS agent's permissions are scoped to"

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:ecs:[^:]+:[0-9]{12}:cluster/", var.cluster_arn))
    error_message = "cluster_arn must be an ECS cluster ARN."
  }
}
variable "vpc_id" {
  type        = string
  description = "VPC of the instances' security group"

  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must be a valid VPC ID (e.g. vpc-0123456789abcdef0)."
  }
}
variable "subnet_ids" {
  type        = list(string)
  description = "Private subnets the group launches into. More than one zone, so a zone without spot capacity for any listed type is not the end of it"

  validation {
    condition     = length(var.subnet_ids) > 0 && alltrue([for id in var.subnet_ids : can(regex("^subnet-[0-9a-f]+$", id))])
    error_message = "subnet_ids must contain at least one valid subnet ID."
  }
}
variable "ami_id" {
  type        = string
  description = "AMI the instances launch from - the ECS-optimized Amazon Linux 2 GPU AMI, which carries the NVIDIA driver and an ECS agent with GPU support"

  validation {
    condition     = can(regex("^ami-[0-9a-f]+$", var.ami_id))
    error_message = "ami_id must be a valid AMI ID (e.g. ami-0123456789abcdef0)."
  }
}
variable "instance_types" {
  type        = list(string)
  default     = ["g4dn.xlarge", "g5.xlarge", "g6.xlarge"]
  description = "GPU instance types the group may launch, the blueprint's list. With lowest-price allocation the group takes the cheapest one that has capacity"

  validation {
    condition     = length(var.instance_types) > 0 && alltrue([for type in var.instance_types : can(regex("^[a-z][a-z0-9-]*\\.[a-z0-9]+$", type))])
    error_message = "instance_types must contain at least one instance type such as g5.xlarge."
  }
}
variable "use_spot" {
  type        = bool
  default     = true
  description = "Whether the instance is spot, the blueprint's use_spot. Spot is much cheaper and can be reclaimed at two minutes' notice; the task's data survives that, because it is on a separate EBS volume rather than the instance"
}
variable "spot_max_price" {
  type        = string
  default     = "0.752"
  description = "Highest hourly spot price the group will pay, in US dollars - the blueprint's spot_price. No instance launches while every listed type costs more"

  validation {
    condition     = can(regex("^[0-9]+(\\.[0-9]+)?$", var.spot_max_price)) && tonumber(var.spot_max_price) > 0
    error_message = "spot_max_price must be a positive decimal number of US dollars, such as 0.752."
  }
}
variable "min_size" {
  type        = number
  default     = 0
  description = "Minimum size of the group. Zero, as the blueprint had it, which is what lets it scale to nothing when idle"

  validation {
    condition     = var.min_size >= 0
    error_message = "min_size must not be negative."
  }
}
variable "max_size" {
  type        = number
  default     = 1
  description = "Maximum size of the group. One, as the blueprint had it: the admin functions treat the group as a single instance, and the task's volume can be attached to only one"

  validation {
    condition     = var.max_size >= 1
    error_message = "max_size must be at least 1."
  }
}
variable "desired_capacity" {
  type        = number
  default     = 1
  description = "Instances launched when the group is created. Only the starting value - see the ignore_changes on the group"

  validation {
    condition     = var.desired_capacity >= 0
    error_message = "desired_capacity must not be negative."
  }
  validation {
    condition     = var.desired_capacity >= var.min_size && var.desired_capacity <= var.max_size
    error_message = "desired_capacity must be between min_size and max_size."
  }
}
variable "root_volume_size" {
  type        = number
  default     = 50
  description = "Root volume size in GiB, 50 as the blueprint had it. Docker's images live here, ComfyUI's image among them"

  validation {
    condition     = var.root_volume_size >= 30
    error_message = "root_volume_size must be at least 30 GiB - the ECS GPU AMI's own root snapshot is that size."
  }
}
variable "instance_policy_arns" {
  type = list(string)
  default = [
    "arn:aws:iam::aws:policy/AmazonEC2FullAccess",
    "arn:aws:iam::aws:policy/AmazonSSMManagedEC2InstanceDefaultPolicy",
  ]
  description = <<-DESC
    Managed policies on the instance role, the blueprint's two - kept as it had them rather than narrowed
    (rules.md A-5).

    AmazonEC2FullAccess is the blueprint's own choice, with its own comment beside it asking whether less would
    do. It is what the REX-Ray plugin creates, attaches, detaches and tags the task's volume with, and the
    plugin's exact needs could not be exercised from here. Containers cannot reach it: the user data blocks
    the instance metadata address for them, and the task has a role of its own. Narrowing it means replacing it
    with the EC2 volume and snapshot actions REX-Ray documents for its EBS driver, and confirming a task still
    starts and moves between zones.

    AmazonSSMManagedEC2InstanceDefaultPolicy is what the admin page's Restart Docker button needs: it sends
    the restart through SSM Run Command.
  DESC

  validation {
    condition     = alltrue([for arn in var.instance_policy_arns : can(regex("^arn:aws[a-z-]*:iam::", arn))])
    error_message = "instance_policy_arns must contain IAM policy ARNs."
  }
}
variable "security_group_name" {
  type        = string
  description = "Name of the instances' security group"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.security_group_name)) && !startswith(var.security_group_name, "sg-")
    error_message = "security_group_name must be 1-255 characters from the set EC2 accepts for a security group name (no apostrophe) and must not start with \"sg-\"."
  }
}
variable "security_group_description" {
  type        = string
  default     = "Security Group for ASG"
  description = "Description of the instances' security group, as the blueprint wrote it. Changing it replaces the group (rules.md F-1)"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.security_group_description))
    error_message = "security_group_description must be 1-255 characters from the set EC2 accepts for a security group description. An apostrophe is not allowed - EC2 rejects it only at apply."
  }
}
variable "docker_volume_plugin" {
  type        = string
  default     = "public.ecr.aws/j1l5j1d1/rexray-ebs"
  description = "Docker volume plugin the user data installs, the blueprint's REX-Ray EBS build. The task definition names the same string as its volume driver, so the two have to agree"

  validation {
    condition     = can(regex("^[a-z0-9.-]+(/[a-z0-9._-]+)+(:[A-Za-z0-9._-]+)?$", var.docker_volume_plugin))
    error_message = "docker_volume_plugin must be an image reference such as public.ecr.aws/j1l5j1d1/rexray-ebs."
  }
}
variable "auto_scale_down" {
  type        = bool
  default     = true
  description = "Whether the group scales to zero after idle_minutes of CPU below idle_cpu_threshold_percent, the blueprint's auto_scale_down"
}
variable "idle_cpu_threshold_percent" {
  type        = number
  default     = 1
  description = "Average CPU below which the instance counts as idle, 1% as the blueprint had it. A GPU workload can be busy at low CPU; this measures whether anyone is using ComfyUI at all"

  validation {
    condition     = var.idle_cpu_threshold_percent > 0 && var.idle_cpu_threshold_percent < 100
    error_message = "idle_cpu_threshold_percent must be between 0 and 100."
  }
}
variable "idle_minutes" {
  type        = number
  default     = 60
  description = "Consecutive idle minutes before the scale-in, 60 as the blueprint had it"

  validation {
    # One-minute periods, and CloudWatch evaluates at most a day's worth of them.
    condition     = var.idle_minutes >= 1 && var.idle_minutes <= 1440 && floor(var.idle_minutes) == var.idle_minutes
    error_message = "idle_minutes must be a whole number of minutes between 1 and 1440."
  }
}
variable "schedule_auto_scaling" {
  type        = bool
  default     = false
  description = "Whether the group is scaled down and up on a schedule, the blueprint's schedule_auto_scaling"
}
variable "schedule_timezone" {
  type        = string
  default     = "UTC"
  description = "IANA time zone the schedule is read in, UTC as the blueprint's default"

  validation {
    condition     = can(regex("^[A-Za-z_]+(/[A-Za-z0-9_+-]+)*$", var.schedule_timezone))
    error_message = "schedule_timezone must be an IANA time zone name such as Asia/Seoul or UTC."
  }
}
variable "schedule_scale_up" {
  type        = string
  default     = "0 9 * * 1-5"
  description = "Cron expression for setting the group to one instance, weekdays at 09:00 as the blueprint's default"

  validation {
    condition     = length(split(" ", trimspace(var.schedule_scale_up))) == 5
    error_message = "schedule_scale_up must be a five-field Unix cron expression such as \"0 9 * * 1-5\"."
  }
}
variable "schedule_scale_down" {
  type        = string
  default     = "0 18 * * *"
  description = "Cron expression for setting the group to zero, every day at 18:00 as the blueprint's default"

  validation {
    condition     = length(split(" ", trimspace(var.schedule_scale_down))) == 5
    error_message = "schedule_scale_down must be a five-field Unix cron expression such as \"0 18 * * *\"."
  }
}
variable "capacity_provider_name" {
  type        = string
  description = "Name of the ECS capacity provider"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,255}$", var.capacity_provider_name)) && !can(regex("^(aws|ecs|fargate)", lower(var.capacity_provider_name)))
    error_message = "capacity_provider_name must be 1-255 letters, digits, hyphens and underscores, and must not begin with aws, ecs or fargate - ECS reserves those prefixes."
  }
}
