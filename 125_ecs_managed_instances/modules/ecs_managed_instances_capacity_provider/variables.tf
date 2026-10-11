variable "name" {
  type        = string
  description = "Name of the capacity provider, also the prefix of the infrastructure role's generated name"

  validation {
    # ECS reserves the aws, ecs and fargate prefixes for capacity provider names.
    condition     = can(regex("^[a-zA-Z0-9_-]{1,255}$", var.name)) && !can(regex("^(?i)(aws|ecs|fargate)", var.name))
    error_message = "name must be 1-255 characters of letters, digits, hyphens and underscores, and must not begin with aws, ecs or fargate, which ECS reserves."
  }
}
variable "cluster_name" {
  type        = string
  description = "Cluster the capacity provider belongs to. A managed instances provider is scoped to one cluster"

  validation {
    condition     = length(var.cluster_name) > 0
    error_message = "cluster_name must not be empty."
  }
}
variable "vpc_id" {
  type        = string
  description = "VPC the instances' security group is created in"

  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must be a valid VPC ID (e.g. vpc-0123456789abcdef0)."
  }
}
variable "subnet_ids" {
  type        = list(string)
  description = "Private subnets the instances are launched into"

  validation {
    condition     = length(var.subnet_ids) > 0 && alltrue([for id in var.subnet_ids : can(regex("^subnet-[0-9a-f]+$", id))])
    error_message = "subnet_ids must contain at least one valid subnet ID."
  }
}
variable "security_group_name" {
  type        = string
  default     = "ecs-managed-instances-sg"
  description = "Name of the instances' security group. The _monolithic template let EC2 generate one"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.security_group_name)) && !startswith(var.security_group_name, "sg-")
    error_message = "security_group_name must be 1-255 characters from the set AWS accepts for a security group name (no apostrophe) and must not start with \"sg-\" (rules.md F-1)."
  }
}
variable "instance_role_name_prefix" {
  type        = string
  default     = "ecsInstanceRole-"
  description = "Prefix for the instance role and instance profile names"

  validation {
    # The infrastructure role's managed policy can pass only roles matching role/ecsInstanceRole*. A role
    # outside that pattern is created fine and then never reaches an instance (rules.md B-1).
    condition     = startswith(var.instance_role_name_prefix, "ecsInstanceRole") && can(regex("^[a-zA-Z0-9+=,.@_-]{15,38}$", var.instance_role_name_prefix))
    error_message = "instance_role_name_prefix must start with ecsInstanceRole and be at most 38 characters. AmazonECSInfrastructureRolePolicyForManagedInstances grants iam:PassRole only on role/ecsInstanceRole*, so any other name leaves ECS unable to launch an instance with it."
  }
}
variable "instance_role_policy_arns" {
  type = list(string)
  default = [
    "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role",
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
  ]
  description = "Managed policies attached to the instance role, as the _monolithic template attached them. The first is what lets the ECS agent register; the second is what lets a person reach an instance through Session Manager"

  validation {
    condition     = alltrue([for arn in var.instance_role_policy_arns : can(regex("^arn:aws:iam::(aws|[0-9]{12}):policy/", arn))])
    error_message = "instance_role_policy_arns must contain valid IAM managed policy ARNs."
  }
}
variable "capacity_option_type" {
  type        = string
  default     = "ON_DEMAND"
  description = "Purchasing option for the instances, as the _monolithic template had it. Changing it replaces the capacity provider"

  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.capacity_option_type)
    error_message = "capacity_option_type must be ON_DEMAND or SPOT. RESERVED needs a capacity_reservations block this module does not expose."
  }
}
variable "monitoring" {
  type        = string
  default     = "BASIC"
  description = "CloudWatch monitoring level for the instances, as the _monolithic template had it"

  validation {
    condition     = contains(["BASIC", "DETAILED"], var.monitoring)
    error_message = "monitoring must be BASIC or DETAILED."
  }
}
variable "storage_size_gib" {
  type        = number
  default     = 30
  description = "Root volume size for each instance, as the _monolithic template had it"

  validation {
    condition     = var.storage_size_gib >= 30
    error_message = "storage_size_gib must be at least 30 GiB."
  }
}
variable "vcpu_count" {
  type = object({
    min = number
    max = number
  })
  default = {
    min = 1
    max = 4
  }
  description = "vCPU range ECS chooses instance types from, as the _monolithic template had it. The largest task here asks for half a vCPU"

  validation {
    condition     = var.vcpu_count.min >= 1 && var.vcpu_count.max >= var.vcpu_count.min
    error_message = "vcpu_count.min must be at least 1 and vcpu_count.max at least vcpu_count.min."
  }
}
variable "memory_mib" {
  type = object({
    min = number
    max = number
  })
  default = {
    min = 2048
    max = 8192
  }
  description = "Memory range ECS chooses instance types from, as the _monolithic template had it. Both tasks together ask for 1.5 GiB, so the minimum leaves room for the agent and one of each"

  validation {
    condition     = var.memory_mib.min >= 1024 && var.memory_mib.max >= var.memory_mib.min
    error_message = "memory_mib.min must be at least 1024 and memory_mib.max at least memory_mib.min."
  }
}
variable "scale_in_after_seconds" {
  type        = number
  default     = 0
  description = "Seconds an idle instance is kept before ECS terminates it. 0, as the _monolithic template had it, terminates immediately; -1 turns idle termination off"

  validation {
    condition     = var.scale_in_after_seconds == -1 || (var.scale_in_after_seconds >= 0 && var.scale_in_after_seconds <= 3600)
    error_message = "scale_in_after_seconds must be -1 or between 0 and 3600."
  }
}
variable "auto_repair_actions_status" {
  type        = string
  default     = "ENABLED"
  description = "Whether ECS replaces instances it finds impaired, as the _monolithic template's AutoRepairConfiguration had it"

  validation {
    condition     = contains(["ENABLED", "DISABLED"], var.auto_repair_actions_status)
    error_message = "auto_repair_actions_status must be ENABLED or DISABLED."
  }
}
