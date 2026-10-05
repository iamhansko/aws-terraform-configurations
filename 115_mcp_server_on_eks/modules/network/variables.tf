variable "region" {
  type        = string
  description = "Region the subnets are placed in. Passed in rather than read from a data source here, so the module has no data source of its own - a data source inside a module the caller orders with depends_on is deferred to apply, which is a trap worth avoiding by default (rules.md D-6)"

  validation {
    condition     = can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]$", var.region))
    error_message = "region must be a valid AWS region such as ap-northeast-2."
  }
}
variable "vpc_cidr_block" {
  type        = string
  default     = "10.0.0.0/16"
  description = "CIDR block for the VPC, as the _monolithic template had it"

  validation {
    condition     = can(cidrhost(var.vpc_cidr_block, 0))
    error_message = "vpc_cidr_block must be a valid IPv4 CIDR block."
  }
}
variable "availability_zone_suffixes" {
  type        = list(string)
  default     = ["a", "c", "d"]
  description = <<-DESC
    Availability zones, by suffix. Three, as the _monolithic template's AzMapping had them - and a, c, d
    rather than a, b, c, which is what that mapping used.

    Three is right here for a reason worth writing down: rules.md C-3 says the zone count is decided by what
    the project puts in the network. The clusters this project creates are built by a script on the workbench
    with eksctl, and that script spreads them across the zones it finds - so the network has to offer enough
    of them, and two would cap the demo.
  DESC

  validation {
    condition     = length(var.availability_zone_suffixes) >= 2
    error_message = "availability_zone_suffixes must name at least two zones. An EKS cluster requires subnets in two, and the script that builds them here reads what the VPC offers."
  }
  validation {
    condition     = alltrue([for suffix in var.availability_zone_suffixes : can(regex("^[a-z]$", suffix))])
    error_message = "availability_zone_suffixes must each be a single lowercase letter."
  }
  validation {
    condition     = length(distinct(var.availability_zone_suffixes)) == length(var.availability_zone_suffixes)
    error_message = "availability_zone_suffixes must not repeat a zone."
  }
}
variable "public_subnet_newbits" {
  type        = number
  default     = 8
  description = "Bits added to the VPC prefix for each public subnet. Eight on a /16 gives /24s, which is what the _monolithic template's AzMapping listed literally - derived here instead, so changing the VPC CIDR does not leave the subnets pointing outside it (rules.md B-1)"

  validation {
    condition     = var.public_subnet_newbits >= 1 && var.public_subnet_newbits <= 16
    error_message = "public_subnet_newbits must be between 1 and 16."
  }
}
variable "private_subnet_index_offset" {
  type        = number
  default     = 10
  description = "Where the private subnets start in the same split. The _monolithic template used 10.0.0-2.0/24 for public and 10.0.10-12.0/24 for private, which is an offset of ten - kept because the gap is deliberate: it leaves room to add public zones without renumbering the private ones"

  validation {
    condition     = var.private_subnet_index_offset >= 1
    error_message = "private_subnet_index_offset must be at least 1, or the public and private subnets would overlap."
  }
}
variable "nat_availability_zone_suffixes" {
  type        = list(string)
  default     = ["a", "c"]
  description = <<-DESC
    Zones the regional NAT gateway is given an address in. Two, as the _monolithic template wired them.

    That template also created a third Elastic IP for the third zone and attached it to nothing, so it sat
    allocated and billed with no route through it (rules.md A-5). Deriving the addresses from this list is
    what makes that impossible: one address per entry, no more.

    A regional NAT gateway serves the whole region regardless, so a private subnet in a zone not listed here
    still reaches the internet - through an address in another zone, which costs a cross-zone hop.
  DESC

  validation {
    condition     = length(var.nat_availability_zone_suffixes) >= 1
    error_message = "nat_availability_zone_suffixes must name at least one zone - a regional NAT gateway needs an address somewhere."
  }
  validation {
    condition     = alltrue([for suffix in var.nat_availability_zone_suffixes : can(regex("^[a-z]$", suffix))])
    error_message = "nat_availability_zone_suffixes must each be a single lowercase letter."
  }
  validation {
    # The pair is what can be wrong: an address in a zone with no subnet is an address for nothing
    # (rules.md B-1).
    condition     = length(setsubtract(var.nat_availability_zone_suffixes, var.availability_zone_suffixes)) == 0
    error_message = "nat_availability_zone_suffixes must be drawn from availability_zone_suffixes. An address in a zone the VPC has no subnet in is an Elastic IP with nothing routed through it, which is what the _monolithic template's third one was."
  }
}
variable "enable_dns_support" {
  type        = bool
  default     = true
  description = "Whether the VPC resolves the Amazon-provided DNS, as the _monolithic template had it"
}
variable "enable_dns_hostnames" {
  type        = bool
  default     = true
  description = "Whether instances get public DNS names, as the _monolithic template had it. Needed by the EKS clusters the workbench script builds: the kubelet registers under its private DNS name"
}
variable "vpc_name" {
  type        = string
  description = "Name tag on the VPC"

  validation {
    condition     = length(var.vpc_name) > 0
    error_message = "vpc_name must not be empty."
  }
}
variable "internet_gateway_name" {
  type        = string
  default     = "igw"
  description = "Name tag on the internet gateway, as the _monolithic template had it"

  validation {
    condition     = length(var.internet_gateway_name) > 0
    error_message = "internet_gateway_name must not be empty."
  }
}
variable "public_subnet_name_prefix" {
  type        = string
  default     = "public-subnet"
  description = "Name tag prefix for the public subnets; the zone suffix is appended, as the _monolithic template's literal names had it"

  validation {
    condition     = length(var.public_subnet_name_prefix) > 0
    error_message = "public_subnet_name_prefix must not be empty."
  }
}
variable "private_subnet_name_prefix" {
  type        = string
  default     = "private-subnet"
  description = "Name tag prefix for the private subnets"

  validation {
    condition     = length(var.private_subnet_name_prefix) > 0
    error_message = "private_subnet_name_prefix must not be empty."
  }
}
variable "public_route_table_name" {
  type        = string
  default     = "public-rt"
  description = "Name tag on the public route table"

  validation {
    condition     = length(var.public_route_table_name) > 0
    error_message = "public_route_table_name must not be empty."
  }
}
variable "private_route_table_name" {
  type        = string
  default     = "private-rt"
  description = "Name tag on the private route table"

  validation {
    condition     = length(var.private_route_table_name) > 0
    error_message = "private_route_table_name must not be empty."
  }
}
variable "nat_gateway_name" {
  type        = string
  default     = "regional-natgw"
  description = "Name tag on the NAT gateway, as the _monolithic template had it"

  validation {
    condition     = length(var.nat_gateway_name) > 0
    error_message = "nat_gateway_name must not be empty."
  }
}
variable "subnet_tags" {
  type        = map(string)
  default     = {}
  description = "Tags merged into every subnet. Empty here, unlike the load balancer projects: the clusters in this VPC are created by eksctl from the workbench, and eksctl writes its own kubernetes.io/role tags onto the subnets it chooses (rules.md G-1 covers the case where Terraform has to write them instead)"

  validation {
    condition     = alltrue([for key in keys(var.subnet_tags) : length(key) > 0 && !startswith(lower(key), "aws:")])
    error_message = "subnet_tags keys must be non-empty and must not use the reserved \"aws:\" prefix."
  }
}
