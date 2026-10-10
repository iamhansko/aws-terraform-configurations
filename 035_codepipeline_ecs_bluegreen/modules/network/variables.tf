variable "region" {
  type        = string
  description = "Region the availability zone letters are appended to. Passed in rather than read from a data source here, so that this module contains no data source at all and nothing in it is deferred to apply when the caller orders it with depends_on (rules.md D-6)"

  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]$", var.region))
    error_message = "region must be an AWS region code such as ap-northeast-2."
  }
}
variable "availability_zone_suffixes" {
  type        = list(string)
  default     = ["a", "b"]
  description = "Availability zone letters, one per subnet pair. Two of them, which is what this project needs: an Application Load Balancer requires subnets in at least two zones, and nothing here requires a third (rules.md C-3)"

  validation {
    condition     = length(var.availability_zone_suffixes) == 2
    error_message = "availability_zone_suffixes must contain exactly two letters. The subnet CIDR blocks and every per-zone output in this module are written out for two zones, so a third would be silently ignored rather than created."
  }
  validation {
    condition     = alltrue([for suffix in var.availability_zone_suffixes : can(regex("^[a-z]$", suffix))])
    error_message = "availability_zone_suffixes must each be a single lowercase letter, appended to region to form a zone name."
  }
}
variable "vpc_cidr_block" {
  type        = string
  default     = "10.10.0.0/16"
  description = "CIDR block of the VPC, as the _monolithic template's ResourceMap had it"

  validation {
    condition     = can(cidrhost(var.vpc_cidr_block, 0))
    error_message = "vpc_cidr_block must be a valid IPv4 CIDR block."
  }
}
variable "subnet_newbits" {
  type        = number
  default     = 8
  description = "Bits added to the VPC mask to produce each subnet. Eight on a /16 gives the four /24s the conversion's Fn::Cidr expression worked out to"

  validation {
    condition     = var.subnet_newbits >= 1 && var.subnet_newbits <= 12 && floor(var.subnet_newbits) == var.subnet_newbits
    error_message = "subnet_newbits must be a whole number between 1 and 12. Four subnets are carved out, so the value also has to leave room for at least four blocks."
  }
}
variable "enable_dns_support" {
  type        = bool
  default     = true
  description = "Whether the VPC resolves DNS. Required for enable_dns_hostnames to have any effect, and required for anything in the private subnets to resolve an AWS service endpoint"
}
variable "enable_dns_hostnames" {
  type        = bool
  default     = true
  description = "Whether instances launched in the VPC get DNS hostnames, as the _monolithic template set"
}
variable "vpc_name" {
  type        = string
  description = "Name tag of the VPC"

  validation {
    condition     = length(var.vpc_name) > 0
    error_message = "vpc_name must not be empty."
  }
}
variable "internet_gateway_name" {
  type        = string
  description = "Name tag of the internet gateway"

  validation {
    condition     = length(var.internet_gateway_name) > 0
    error_message = "internet_gateway_name must not be empty."
  }
}
variable "nat_gateway_name" {
  type        = string
  description = "Name tag prefix of the NAT gateways and their elastic IPs. The zone letter is appended"

  validation {
    condition     = length(var.nat_gateway_name) > 0
    error_message = "nat_gateway_name must not be empty."
  }
}
variable "public_subnet_name" {
  type        = string
  description = "Name tag prefix of the public subnets. The zone letter is appended"

  validation {
    condition     = length(var.public_subnet_name) > 0
    error_message = "public_subnet_name must not be empty."
  }
}
variable "private_subnet_name" {
  type        = string
  description = "Name tag prefix of the private subnets. The zone letter is appended"

  validation {
    condition     = length(var.private_subnet_name) > 0
    error_message = "private_subnet_name must not be empty."
  }
}
variable "public_route_table_name" {
  type        = string
  description = "Name tag of the single public route table, which both public subnets associate with"

  validation {
    condition     = length(var.public_route_table_name) > 0
    error_message = "public_route_table_name must not be empty."
  }
}
variable "private_route_table_name" {
  type        = string
  description = "Name tag prefix of the two private route tables, one per zone because each points at that zone's own NAT gateway. The zone letter is appended"

  validation {
    condition     = length(var.private_route_table_name) > 0
    error_message = "private_route_table_name must not be empty."
  }
}
