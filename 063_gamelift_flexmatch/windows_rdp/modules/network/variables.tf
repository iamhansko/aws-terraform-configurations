variable "name_prefix" {
  type        = string
  default     = "gamelift-flexmatch"
  description = "Prefix for the Name tag of every resource in this module (e.g. <prefix>-vpc, <prefix>-public-subnet-a)"

  validation {
    condition     = length(var.name_prefix) > 0 && length(var.name_prefix) <= 200
    error_message = "name_prefix must be 1-200 characters, leaving room for the suffixes inside the 256 character tag value limit."
  }
}
variable "aws_region" {
  type        = string
  description = "Region the VPC is created in. The availability zones are this plus each suffix in availability_zone_suffixes"

  validation {
    condition     = can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]$", var.aws_region))
    error_message = "aws_region must be a region code such as ap-northeast-2."
  }
}
variable "availability_zone_suffixes" {
  type        = list(string)
  default     = ["a", "c"]
  description = "The two AZ letters, in order: the first holds the *_a subnets and the second the *_c subnets. a and c, not a and b, because that is what the _monolithic template used - the sibling template variant of this project uses a and b, and the difference is the original's"

  validation {
    condition     = length(var.availability_zone_suffixes) == 2
    error_message = "availability_zone_suffixes must contain exactly two entries, because this module declares one public and one private subnet per zone by name rather than by for_each."
  }
  validation {
    condition     = alltrue([for suffix in var.availability_zone_suffixes : can(regex("^[a-z]$", suffix))])
    error_message = "availability_zone_suffixes entries must each be a single lowercase letter (e.g. a), which is appended to the region name to form the zone."
  }
  validation {
    condition     = length(distinct(var.availability_zone_suffixes)) == 2
    error_message = "availability_zone_suffixes entries must differ. ElastiCache and the VPC-attached Lambda functions are spread over these two zones, and one zone twice is one zone."
  }
}
variable "vpc_cidr_block" {
  type        = string
  default     = "10.0.0.0/16"
  description = "CIDR block for the VPC, as the _monolithic template had it"

  validation {
    condition     = can(cidrhost(var.vpc_cidr_block, 0))
    error_message = "vpc_cidr_block must be a valid IPv4 CIDR block (e.g. 10.0.0.0/16)."
  }
}
variable "public_subnet_a_cidr_block" {
  type        = string
  default     = "10.0.0.0/24"
  description = "CIDR block of the public subnet in the first zone (the template's AzMapping a.PublicSubnetCidr)"

  validation {
    condition     = can(cidrhost(var.public_subnet_a_cidr_block, 0))
    error_message = "public_subnet_a_cidr_block must be a valid IPv4 CIDR block (e.g. 10.0.0.0/24)."
  }
}
variable "public_subnet_c_cidr_block" {
  type        = string
  default     = "10.0.4.0/24"
  description = "CIDR block of the public subnet in the second zone (the template's AzMapping c.PublicSubnetCidr)"

  validation {
    condition     = can(cidrhost(var.public_subnet_c_cidr_block, 0))
    error_message = "public_subnet_c_cidr_block must be a valid IPv4 CIDR block (e.g. 10.0.4.0/24)."
  }
}
variable "private_subnet_a_cidr_block" {
  type        = string
  default     = "10.0.1.0/24"
  description = "CIDR block of the private subnet in the first zone (the template's AzMapping a.PrivateSubnetCidr)"

  validation {
    condition     = can(cidrhost(var.private_subnet_a_cidr_block, 0))
    error_message = "private_subnet_a_cidr_block must be a valid IPv4 CIDR block (e.g. 10.0.1.0/24)."
  }
}
variable "private_subnet_c_cidr_block" {
  type        = string
  default     = "10.0.5.0/24"
  description = "CIDR block of the private subnet in the second zone (the template's AzMapping c.PrivateSubnetCidr)"

  validation {
    condition     = can(cidrhost(var.private_subnet_c_cidr_block, 0))
    error_message = "private_subnet_c_cidr_block must be a valid IPv4 CIDR block (e.g. 10.0.5.0/24)."
  }
  validation {
    # Four subnets carved by hand from one VPC; two of them equal is an
    # InvalidSubnet.Conflict at CreateSubnet, after the VPC and gateway exist.
    condition = length(distinct([
      var.public_subnet_a_cidr_block, var.public_subnet_c_cidr_block,
      var.private_subnet_a_cidr_block, var.private_subnet_c_cidr_block,
    ])) == 4
    error_message = "The four subnet CIDR blocks must all differ."
  }
}
