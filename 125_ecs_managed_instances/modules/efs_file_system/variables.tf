variable "name" {
  type        = string
  default     = "shlink"
  description = "Name tag of the file system, as the _monolithic template had it, and the base name of its two security groups"

  validation {
    condition     = can(regex("^[a-zA-Z0-9._-]{1,200}$", var.name))
    error_message = "name must be 1-200 characters of letters, digits, dots, underscores and hyphens, so the security group names derived from it stay valid (rules.md F-1)."
  }
}
variable "vpc_id" {
  type        = string
  description = "VPC the mount targets' and the clients' security groups are created in"

  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must be a valid VPC ID (e.g. vpc-0123456789abcdef0)."
  }
}
variable "subnet_ids_by_zone" {
  type        = map(string)
  description = "Subnets to create a mount target in, keyed by zone letter. A map, because the IDs are the network module's output and unknown at plan, while the keys are not (rules.md B-8). One per zone a task can land in - a task in a zone with no mount target fails to mount"

  validation {
    condition     = length(var.subnet_ids_by_zone) > 0 && alltrue([for id in values(var.subnet_ids_by_zone) : can(regex("^subnet-[0-9a-f]+$", id))])
    error_message = "subnet_ids_by_zone must contain at least one valid subnet ID."
  }
  validation {
    condition     = alltrue([for zone in keys(var.subnet_ids_by_zone) : can(regex("^[a-z]$", zone))])
    error_message = "subnet_ids_by_zone keys must be single zone letters."
  }
}
variable "ingress_source_security_groups" {
  type        = map(string)
  default     = {}
  description = "Further security groups allowed to mount, keyed by a caller-chosen label, in addition to the client group this module creates. The _monolithic template allowed the managed instances' group, and that is what goes here (rules.md B-8)"

  validation {
    condition     = alltrue([for label in keys(var.ingress_source_security_groups) : can(regex("^[a-zA-Z0-9._-]+$", label))])
    error_message = "ingress_source_security_groups keys are labels used in rule descriptions and resource addresses, so each must be letters, digits, dots, underscores or hyphens (rules.md F-1)."
  }
  validation {
    condition     = alltrue([for id in values(var.ingress_source_security_groups) : can(regex("^sg-[0-9a-f]+$", id))])
    error_message = "ingress_source_security_groups must contain valid security group IDs."
  }
}
variable "backup_enabled" {
  type        = bool
  default     = true
  description = "Whether AWS Backup takes daily recovery points of the file system, as the _monolithic template had it. They are what is left of Shlink's data after a terraform destroy"
}
variable "posix_uid" {
  type        = number
  default     = 1001
  description = "POSIX user every NFS operation through the access point runs as, as the _monolithic template had it. The user the Shlink image runs as"

  validation {
    condition     = var.posix_uid >= 0
    error_message = "posix_uid must be zero or greater."
  }
}
variable "posix_gid" {
  type        = number
  default     = 1001
  description = "POSIX group for the same, as the _monolithic template had it"

  validation {
    condition     = var.posix_gid >= 0
    error_message = "posix_gid must be zero or greater."
  }
}
variable "root_directory_path" {
  type        = string
  default     = "/shlink"
  description = "Directory the access point exposes as the root of the mount, created with posix_uid as its owner on first use"

  validation {
    condition     = startswith(var.root_directory_path, "/") && length(var.root_directory_path) <= 100
    error_message = "root_directory_path must be an absolute path of 100 characters or fewer."
  }
}
variable "root_directory_permissions" {
  type        = string
  default     = "0755"
  description = "Mode the root directory is created with, as the _monolithic template had it"

  validation {
    condition     = can(regex("^0?[0-7]{3}$", var.root_directory_permissions))
    error_message = "root_directory_permissions must be an octal mode such as 0755."
  }
}
