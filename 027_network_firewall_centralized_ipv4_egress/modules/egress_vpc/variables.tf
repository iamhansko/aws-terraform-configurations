variable "vpc_cidr_block" {
  type        = string
  default     = "10.0.0.0/16"
  description = "CIDR of the egress VPC, as the _monolithic template had it. It must not overlap the spoke VPC's CIDR: both are propagated into the same transit gateway route table, and an overlap there is not an error - it is a route that wins over the other and traffic that silently goes to the wrong VPC"

  validation {
    condition     = can(cidrhost(var.vpc_cidr_block, 0))
    error_message = "vpc_cidr_block must be a valid IPv4 CIDR block (e.g. 10.0.0.0/16)."
  }
  validation {
    # Six /24s are carved out of this block below. A /22 leaves four, so the
    # fifth cidrsubnet call fails the plan with "Invalid index"; anything longer
    # than /21 cannot hold the layout at all.
    condition     = tonumber(split("/", var.vpc_cidr_block)[1]) >= 16 && tonumber(split("/", var.vpc_cidr_block)[1]) <= 21
    error_message = "vpc_cidr_block must have a prefix length between /16 and /21. This module carves six /24 subnets out of it - two public, two transit gateway attachment, two firewall - and a block shorter than /21 cannot hold them."
  }
}
variable "vpc_name" {
  type        = string
  default     = "egress-vpc"
  description = "Name tag of the VPC, as the _monolithic template tagged it"

  validation {
    condition     = length(var.vpc_name) > 0
    error_message = "vpc_name must not be empty."
  }
}
variable "availability_zone_a" {
  type        = string
  description = "First availability zone, as a full zone name. Passed in rather than assembled from a region lookup here, so that the root can hand the same two zone names to this module and to the spoke VPC - the whole AZ-affinity story depends on the two VPCs being in the same pair of zones (rules.md B-6)"

  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-[0-9][a-z]$", var.availability_zone_a))
    error_message = "availability_zone_a must be a full availability zone name (e.g. us-east-1a), not a suffix."
  }
}
variable "availability_zone_b" {
  type        = string
  description = "Second availability zone, as a full zone name. Must differ from availability_zone_a: Network Firewall requires each of a firewall's subnet mappings to be in a different zone, and two mappings in one zone fail the firewall create with InvalidRequestException"

  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-[0-9][a-z]$", var.availability_zone_b))
    error_message = "availability_zone_b must be a full availability zone name (e.g. us-east-1b), not a suffix."
  }
  validation {
    # A cross-variable condition, because the constraint is about the pair
    # rather than about either value (rules.md B-1).
    condition     = var.availability_zone_b != var.availability_zone_a
    error_message = "availability_zone_b must differ from availability_zone_a. A firewall's subnet mappings must each be in a different zone, and the per-zone route tables this module builds would otherwise pair a firewall endpoint with a NAT gateway in the same zone twice over while leaving a zone with no egress path at all."
  }
}
variable "enable_dns_support" {
  type        = bool
  default     = true
  description = "Whether the Amazon-provided DNS resolver answers inside this VPC, as the _monolithic template set it"
}
variable "enable_dns_hostnames" {
  type        = bool
  default     = true
  description = "Whether instances get public DNS hostnames, as the _monolithic template set it"
}
variable "map_public_ip_on_launch" {
  type        = bool
  default     = true
  description = "Whether the two public subnets auto-assign a public address, as the _monolithic template set them. Nothing in this project launches an instance here - the subnets exist to hold the NAT gateways, which carry Elastic IPs of their own - so this only affects anything added by hand later"
}
variable "internet_gateway_name" {
  type        = string
  default     = "egress-igw"
  description = "Name tag of the internet gateway, as the _monolithic template tagged it"

  validation {
    condition     = length(var.internet_gateway_name) > 0
    error_message = "internet_gateway_name must not be empty."
  }
}
variable "public_subnet_name_prefix" {
  type        = string
  default     = "egress-public-sn"
  description = "Name tag prefix of the two public subnets; the zone letter is appended, giving egress-public-sn-a as the _monolithic template tagged it. These are the NAT gateway subnets - the only ones in this VPC with a route to the internet gateway"

  validation {
    condition     = length(var.public_subnet_name_prefix) > 0
    error_message = "public_subnet_name_prefix must not be empty."
  }
}
variable "peering_subnet_name_prefix" {
  type        = string
  default     = "egress-peering-sn"
  description = <<-DESC
    Name tag prefix of the two transit gateway attachment subnets; the zone letter is appended, giving
    egress-peering-sn-a as the _monolithic template tagged it.

    "peering" is the original's word and is kept for continuity, but nothing here is a VPC peering
    connection - these subnets hold the transit gateway's elastic network interfaces. The distinction
    matters when reading the routes: a transit gateway ENI consults its own subnet's route table, which is
    why these two subnets need route tables of their own rather than sharing one.
  DESC

  validation {
    condition     = length(var.peering_subnet_name_prefix) > 0
    error_message = "peering_subnet_name_prefix must not be empty."
  }
}
variable "firewall_subnet_name_prefix" {
  type        = string
  default     = "egress-firewall-sn"
  description = "Name tag prefix of the two firewall endpoint subnets; the zone letter is appended, giving egress-firewall-sn-a as the _monolithic template tagged it. AWS requires these to be dedicated to Network Firewall - a firewall endpoint cannot inspect traffic whose source or destination is inside its own subnet, so anything else placed here is simply not filtered"

  validation {
    condition     = length(var.firewall_subnet_name_prefix) > 0
    error_message = "firewall_subnet_name_prefix must not be empty."
  }
}
variable "public_route_table_name" {
  type        = string
  default     = "egress-public-rt"
  description = "Name tag of the single route table shared by both public subnets, as the _monolithic template tagged it. One table for both zones is correct here: its two routes - the default to the internet gateway and the spoke return route to the transit gateway - are identical in each zone"

  validation {
    condition     = length(var.public_route_table_name) > 0
    error_message = "public_route_table_name must not be empty."
  }
}
variable "peering_route_table_name_prefix" {
  type        = string
  default     = "egress-peering-rt"
  description = "Name tag prefix of the two transit gateway attachment route tables; the zone letter is appended, giving egress-peering-rt-a as the _monolithic template tagged it. One per zone, because each has to point at the firewall endpoint in its own zone"

  validation {
    condition     = length(var.peering_route_table_name_prefix) > 0
    error_message = "peering_route_table_name_prefix must not be empty."
  }
}
variable "firewall_route_table_name_prefix" {
  type        = string
  default     = "egress-firewall-rt"
  description = "Name tag prefix of the two firewall subnet route tables; the zone letter is appended, giving egress-firewall-rt-a as the _monolithic template tagged it. One per zone, because each has to point at the NAT gateway in its own zone"

  validation {
    condition     = length(var.firewall_route_table_name_prefix) > 0
    error_message = "firewall_route_table_name_prefix must not be empty."
  }
}
variable "nat_gateway_name_prefix" {
  type        = string
  default     = "egress-natgw"
  description = "Name tag prefix of the two NAT gateways; the zone letter is appended, giving egress-natgw-a as the _monolithic template tagged it. Their Elastic IPs are the addresses the whole demo is measured against - a curl from the spoke instance should return one of them"

  validation {
    condition     = length(var.nat_gateway_name_prefix) > 0
    error_message = "nat_gateway_name_prefix must not be empty."
  }
}
