variable "name" {
  type        = string
  default     = "efs"
  description = "Name tag for the EFS file system"
  validation {
    condition     = length(var.name) > 0
    error_message = "name must not be empty."
  }
}
variable "vpc_id" {
  type        = string
  description = "VPC ID where the file system's security group is created"
  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must be a valid VPC ID (e.g. vpc-0123456789abcdef0)."
  }
}
variable "mount_target_subnet_ids" {
  type        = map(string)
  description = "Subnet IDs to place mount targets in, keyed by a caller-chosen label (e.g. { a = subnet-..., b = subnet-... }). EFS allows one mount target per availability zone, and a pod can only mount the file system through the target in its own zone, so this should cover every zone the node group spans. A map rather than a list because these IDs are another module's output, unknown until apply, and for_each needs statically known keys (rules.md B-8)"
  validation {
    condition     = length(var.mount_target_subnet_ids) > 0
    error_message = "mount_target_subnet_ids must contain at least one subnet."
  }
  validation {
    condition     = alltrue([for label in keys(var.mount_target_subnet_ids) : can(regex("^[a-zA-Z0-9._-]+$", label))])
    error_message = "mount_target_subnet_ids keys are labels used in resource addresses, so each must be a non-empty string of letters, digits, dots, underscores or hyphens."
  }
  validation {
    condition     = alltrue([for id in values(var.mount_target_subnet_ids) : can(regex("^subnet-[0-9a-f]+$", id))])
    error_message = "mount_target_subnet_ids must contain valid subnet IDs (e.g. subnet-0123456789abcdef0)."
  }
}
variable "performance_mode" {
  type        = string
  default     = "generalPurpose"
  description = "EFS performance mode. generalPurpose has the lower per-operation latency and is what the CSI driver's access point workflow expects; maxIO trades latency for higher aggregate throughput and cannot be changed after creation"
  validation {
    condition     = contains(["generalPurpose", "maxIO"], var.performance_mode)
    error_message = "performance_mode must be either generalPurpose or maxIO."
  }
}
variable "throughput_mode" {
  type        = string
  default     = "elastic"
  description = "EFS throughput mode. elastic scales with demand and bills per use, which suits a demo that is idle most of the time; provisioned bills for a fixed rate whether it is used or not"
  validation {
    condition     = contains(["bursting", "provisioned", "elastic"], var.throughput_mode)
    error_message = "throughput_mode must be one of: bursting, provisioned, elastic."
  }
}
variable "encrypted" {
  type        = bool
  default     = true
  description = "Whether the file system is encrypted at rest"
}
variable "security_group_name" {
  type        = string
  default     = "efs-sg"
  description = "Name of the security group attached to the mount targets"
  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.security_group_name)) && !startswith(var.security_group_name, "sg-")
    error_message = "security_group_name must be 1-255 characters from the set AWS accepts for a security group name (a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*, no apostrophe) and must not start with \"sg-\", which EC2 reserves for security group IDs."
  }
}
variable "security_group_description" {
  type        = string
  default     = "Security group for the EFS mount targets, admitting NFS from the cluster workloads"
  description = "Description attached to the mount targets' security group"
  validation {
    condition     = length(var.security_group_description) > 0
    error_message = "security_group_description must not be empty."
  }
  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.security_group_description))
    error_message = "security_group_description must be 1-255 characters from the set AWS accepts for a security group description: a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*. An apostrophe is NOT allowed - EC2 rejects the CreateSecurityGroup call with InvalidParameterValue, which otherwise only surfaces at apply time (rules.md F-1)."
  }
}
variable "nfs_port" {
  type        = number
  default     = 2049
  description = "TCP port EFS serves NFS on, opened inbound on the mount targets' security group"
  validation {
    condition     = var.nfs_port > 0 && var.nfs_port <= 65535
    error_message = "nfs_port must be a valid TCP port."
  }
}
variable "ingress_source_security_groups" {
  type        = map(string)
  default     = {}
  description = "Security group IDs allowed inbound on nfs_port, keyed by a caller-chosen label (e.g. { eks_cluster = sg-... }). Preferred over ingress_cidr_blocks because it follows the workloads rather than the address space. A map rather than a list because these IDs are usually another module's output, unknown until apply, and for_each needs statically known keys (rules.md B-8)"
  validation {
    condition     = alltrue([for label in keys(var.ingress_source_security_groups) : can(regex("^[a-zA-Z0-9._-]+$", label))])
    error_message = "ingress_source_security_groups keys are labels used in the rule descriptions and resource addresses, so each must be a non-empty string of letters, digits, dots, underscores or hyphens."
  }
  validation {
    condition     = alltrue([for id in values(var.ingress_source_security_groups) : can(regex("^sg-[0-9a-f]+$", id))])
    error_message = "ingress_source_security_groups must contain valid security group IDs (e.g. sg-0123456789abcdef0)."
  }
}
variable "ingress_cidr_blocks" {
  type        = list(string)
  default     = []
  description = "CIDR blocks allowed inbound on nfs_port, on top of ingress_source_security_groups. A list rather than a map because these are expected to come from configuration (a VPC CIDR variable) and so are known at plan time (rules.md B-8)"
  validation {
    condition     = alltrue([for cidr in var.ingress_cidr_blocks : can(cidrhost(cidr, 0))])
    error_message = "ingress_cidr_blocks must contain valid IPv4 CIDR blocks."
  }
}
