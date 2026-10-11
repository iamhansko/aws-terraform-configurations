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
  default     = "10.2.0.0/16"
  description = "CIDR block for the VPC. 10.2.0.0/16, as the blueprint's ComfyuiVPC had it"

  validation {
    condition     = can(cidrhost(var.vpc_cidr_block, 0))
    error_message = "vpc_cidr_block must be a valid IPv4 CIDR block."
  }
}
variable "availability_zone_suffixes" {
  type        = list(string)
  default     = ["a", "c", "d"]
  description = <<-DESC
    Availability zones, by suffix. Three, because the blueprint's VPC set maxAzs: 3 - and rules.md C-3 says the
    zone count follows what the project runs: an EKS control plane needs two, and Karpenter can only launch a
    GPU instance in a zone that has both a subnet here and capacity for g5/g6, so a third zone is a third
    chance at that capacity.

    Named explicitly rather than "the first three the region lists", which is what CDK did, so the subnets are
    reviewable in the plan.
  DESC

  validation {
    condition     = length(var.availability_zone_suffixes) >= 2
    error_message = "availability_zone_suffixes must name at least two zones, because an EKS cluster requires subnets in two."
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
  default     = 4
  description = "Bits added to the VPC prefix for every subnet. Four on a /16 gives the /20s the blueprint's subnetConfiguration asked for (cidrMask: 20). Pods take their addresses from these subnets through the VPC CNI, so they are sized for pods, not for instances"

  validation {
    condition     = var.public_subnet_newbits >= 1 && var.public_subnet_newbits <= 16
    error_message = "public_subnet_newbits must be between 1 and 16."
  }
}
variable "private_subnet_index_offset" {
  type        = number
  default     = 3
  description = "Where the private subnets start in the same split. Three puts them directly after three public subnets - 10.2.48.0/20, 10.2.64.0/20, 10.2.80.0/20 - which is how CDK laid out the blueprint's VPC, one subnet group after the other"

  validation {
    condition     = var.private_subnet_index_offset >= 1
    error_message = "private_subnet_index_offset must be at least 1, or the public and private subnets would overlap."
  }
}
variable "nat_availability_zone_suffixes" {
  type        = list(string)
  default     = ["a", "c", "d"]
  description = <<-DESC
    Zones the regional NAT gateway is given an address in. Every zone by default, which is what the blueprint's
    natGateways: 3 amounted to: no private subnet takes a cross-zone hop to reach the internet.

    One regional gateway with three addresses rather than three zonal gateways - same egress path per zone, one
    resource, and one private route table instead of three.
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
    error_message = "nat_availability_zone_suffixes must be drawn from availability_zone_suffixes. An address in a zone the VPC has no subnet in is an Elastic IP with nothing routed through it."
  }
}
variable "create_s3_gateway_endpoint" {
  type        = bool
  default     = false
  description = "Whether to add an S3 gateway endpoint on the private route table, as the blueprint's gatewayEndpoints.s3 did. Free, and the difference is large here: every GPU node copies tens of gigabytes of models out of S3 at boot, and without the endpoint each of those gigabytes is billed as NAT gateway data processing"
}
variable "enable_dns_support" {
  type        = bool
  default     = true
  description = "Whether the VPC resolves the Amazon-provided DNS"
}
variable "enable_dns_hostnames" {
  type        = bool
  default     = true
  description = "Whether instances get DNS hostnames. EKS nodes register under their private DNS name, so this stays on"
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
  description = "Name tag on the internet gateway. Also what a CloudFront VPC origin requires to exist in the VPC, even though no origin traffic is routed through it"

  validation {
    condition     = length(var.internet_gateway_name) > 0
    error_message = "internet_gateway_name must not be empty."
  }
}
variable "public_subnet_name_prefix" {
  type        = string
  default     = "public-subnet"
  description = "Name tag prefix for the public subnets; the zone suffix is appended"

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
  description = "Name tag on the NAT gateway"

  validation {
    condition     = length(var.nat_gateway_name) > 0
    error_message = "nat_gateway_name must not be empty."
  }
}
variable "public_subnet_tags" {
  type        = map(string)
  default     = {}
  description = "Tags merged into the public subnets only. Split from the private ones because the load balancer controller discovers subnets by these tags, and kubernetes.io/role/elb on a private subnet - or internal-elb on a public one - lets it place a load balancer in the wrong tier (rules.md G-1)"

  validation {
    condition     = alltrue([for key in keys(var.public_subnet_tags) : length(key) > 0 && !startswith(lower(key), "aws:")])
    error_message = "public_subnet_tags keys must be non-empty and must not use the reserved \"aws:\" prefix."
  }
}
variable "private_subnet_tags" {
  type        = map(string)
  default     = {}
  description = "Tags merged into the private subnets only. See public_subnet_tags for why the tiers are tagged separately"

  validation {
    condition     = alltrue([for key in keys(var.private_subnet_tags) : length(key) > 0 && !startswith(lower(key), "aws:")])
    error_message = "private_subnet_tags keys must be non-empty and must not use the reserved \"aws:\" prefix."
  }
}
