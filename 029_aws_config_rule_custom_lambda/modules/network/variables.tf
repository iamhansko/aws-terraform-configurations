variable "region" {
  type        = string
  description = "Region the subnet's availability zone is named from. Injected by the caller rather than read here with data.aws_region, the same as every other module in this root that needs it"

  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]$", var.region))
    error_message = "region must look like an AWS region (e.g. ap-northeast-2)."
  }
}
variable "availability_zone_suffix" {
  type        = string
  description = "Letter of the availability zone the public subnet is created in, appended to region"

  validation {
    condition     = can(regex("^[a-z]$", var.availability_zone_suffix))
    error_message = "availability_zone_suffix must be a single lowercase letter (e.g. a)."
  }
}
variable "vpc_cidr_block" {
  type        = string
  description = "CIDR block of the VPC. The public subnet is the first /24 carved out of it, so this is the only address decision in the module"

  validation {
    condition     = can(cidrhost(var.vpc_cidr_block, 0))
    error_message = "vpc_cidr_block must be a valid IPv4 CIDR block (e.g. 10.0.0.0/16)."
  }
  validation {
    # /16 is the largest VPC AWS accepts. /24 is the subnet this module carves out, so a longer prefix
    # would ask cidrsubnet for a negative number of new bits and fail the plan with an arithmetic
    # error that does not name this variable.
    #
    # Wrapped in try() because Terraform evaluates every validation block, so a value with no "/" would
    # otherwise fail here with an index error instead of the message above. That value is reported by
    # the first validation; this one stays out of the way.
    condition     = try(tonumber(split("/", var.vpc_cidr_block)[1]) >= 16 && tonumber(split("/", var.vpc_cidr_block)[1]) <= 24, true)
    error_message = "vpc_cidr_block must be between /16 and /24: AWS rejects a VPC larger than /16, and the public subnet is carved out of it as a /24."
  }
}
variable "name_prefix" {
  type        = string
  description = "Prefix of the Name tag on every resource in the module - the VPC, internet gateway, route table and subnet get -vpc, -igw, -public-rt and -public-<zone letter> after it"

  validation {
    # Name tag values may be up to 256 characters; the longest suffix appended is "-public-rt".
    condition     = length(var.name_prefix) > 0 && length(var.name_prefix) <= 240
    error_message = "name_prefix must be 1-240 characters, so the longest Name tag built from it stays within the 256 characters EC2 allows for a tag value."
  }
}
