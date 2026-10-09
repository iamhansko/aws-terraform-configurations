variable "name" {
  type        = string
  default     = "app"
  description = "Prefix for every Name tag in this VPC. The _monolithic template tagged these app-vpc, app-private-sn-a, app-private-sn-b and app-rt"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.name))
    error_message = "name must be lowercase letters, digits or hyphens and must not start or end with a hyphen."
  }
}
variable "region" {
  type        = string
  description = "Region name, prefixed to each zone suffix to form an availability zone name. Passed in rather than read here, for the same reason as in the egress VPC module (rules.md D-6/I-3)"

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.region))
    error_message = "region must look like an AWS region (e.g. ap-northeast-2)."
  }
}
variable "availability_zone_suffixes" {
  type        = list(string)
  description = "Zone suffixes this VPC spans, used as the subnets' for_each keys and therefore configuration literals (rules.md B-8)"

  validation {
    condition     = length(var.availability_zone_suffixes) >= 2
    error_message = "availability_zone_suffixes must name at least two zones; the transit gateway attachment is placed in one subnet per zone and a single-zone attachment loses connectivity with that zone."
  }
  validation {
    condition     = alltrue([for suffix in var.availability_zone_suffixes : can(regex("^[a-z]$", suffix))])
    error_message = "each availability_zone_suffixes entry must be a single lowercase letter."
  }
}
variable "vpc_cidr_block" {
  type        = string
  description = "Primary CIDR block of the app VPC. The egress VPC's public route table carries a return route to this block, which the root writes - so this value reaches two places and is defined in one (rules.md B-5)"

  validation {
    condition     = can(cidrhost(var.vpc_cidr_block, 0))
    error_message = "vpc_cidr_block must be a valid IPv4 CIDR block."
  }
}
variable "private_subnet_cidr_blocks" {
  type        = map(string)
  description = "Private subnet CIDR blocks by zone suffix. These hold both the transit gateway attachment and the workbench; there is no public tier in this VPC at all"

  validation {
    condition     = alltrue([for cidr in values(var.private_subnet_cidr_blocks) : can(cidrhost(cidr, 0))])
    error_message = "every private_subnet_cidr_blocks value must be a valid IPv4 CIDR block."
  }
  validation {
    condition     = alltrue([for suffix in var.availability_zone_suffixes : contains(keys(var.private_subnet_cidr_blocks), suffix)])
    error_message = "private_subnet_cidr_blocks must have an entry for every suffix in availability_zone_suffixes, or the subnet resource's for_each fails the plan with Invalid index."
  }
}
