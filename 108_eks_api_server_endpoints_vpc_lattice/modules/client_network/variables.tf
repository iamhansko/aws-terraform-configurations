variable "region" {
  type        = string
  description = "Region the subnets are placed in. Passed in rather than read from a data source here, so the module has no data source of its own - one inside a module the caller orders with depends_on is deferred to apply (rules.md D-6)"

  validation {
    condition     = can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]$", var.region))
    error_message = "region must be a valid AWS region such as ap-northeast-2."
  }
}
variable "vpc_cidr_block" {
  type        = string
  default     = "192.168.0.0/16"
  description = "CIDR block for the client VPC. It must not overlap the cluster VPC's - not because the two are routed to each other, which is the point of using Lattice, but because a client resolving the API server's name to an address inside its own range would never leave the VPC"

  validation {
    condition     = can(cidrhost(var.vpc_cidr_block, 0))
    error_message = "vpc_cidr_block must be a valid IPv4 CIDR block."
  }
}
variable "availability_zone_suffixes" {
  type        = list(string)
  default     = ["a", "c"]
  description = "Zones the client VPC spans, a and c as the _monolithic template had them. Two, because the Lattice endpoint needs interfaces in two"

  validation {
    condition     = length(var.availability_zone_suffixes) >= 2
    error_message = "availability_zone_suffixes must name at least two zones - a VPC endpoint needs interfaces in two."
  }
  validation {
    condition     = alltrue([for suffix in var.availability_zone_suffixes : can(regex("^[a-z]$", suffix))])
    error_message = "availability_zone_suffixes must each be a single lowercase letter."
  }
}
variable "subnet_newbits" {
  type        = number
  default     = 8
  description = "Bits added to the VPC prefix for each subnet. Eight on a /16 gives /24s, which is what the _monolithic template listed literally - derived here so changing the VPC CIDR moves the subnets with it (rules.md B-1)"

  validation {
    condition     = var.subnet_newbits >= 1 && var.subnet_newbits <= 16
    error_message = "subnet_newbits must be between 1 and 16."
  }
}
variable "vpc_name" {
  type        = string
  description = "Name tag on the client VPC"

  validation {
    condition     = length(var.vpc_name) > 0
    error_message = "vpc_name must not be empty."
  }
}
variable "public_subnet_name_prefix" {
  type        = string
  default     = "client-public-subnet"
  description = "Name tag prefix for the subnets; the zone suffix is appended"

  validation {
    condition     = length(var.public_subnet_name_prefix) > 0
    error_message = "public_subnet_name_prefix must not be empty."
  }
}
variable "internet_gateway_name" {
  type        = string
  default     = "client-igw"
  description = "Name tag on the internet gateway"

  validation {
    condition     = length(var.internet_gateway_name) > 0
    error_message = "internet_gateway_name must not be empty."
  }
}
variable "route_table_name" {
  type        = string
  default     = "client-public-rt"
  description = "Name tag on the route table"

  validation {
    condition     = length(var.route_table_name) > 0
    error_message = "route_table_name must not be empty."
  }
}
