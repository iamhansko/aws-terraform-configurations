variable "vpc_cidr_block" {
  type        = string
  default     = "172.16.0.0/16"
  description = <<-DESC
    CIDR of the spoke VPC, as the _monolithic template had it.

    It is in a different RFC 1918 block from the egress VPC's 10.0.0.0/16, and that is not decoration. Both
    VPCs propagate their CIDRs into the same transit gateway route table, and the egress VPC's public route
    table carries a route for this CIDR back to the transit gateway. Overlapping the two would not fail a
    plan or an apply - it would produce a more specific route winning somewhere and return traffic going to
    the wrong VPC.
  DESC

  validation {
    condition     = can(cidrhost(var.vpc_cidr_block, 0))
    error_message = "vpc_cidr_block must be a valid IPv4 CIDR block (e.g. 172.16.0.0/16)."
  }
  validation {
    condition     = tonumber(split("/", var.vpc_cidr_block)[1]) >= 16 && tonumber(split("/", var.vpc_cidr_block)[1]) <= 23
    error_message = "vpc_cidr_block must have a prefix length between /16 and /23. This module carves two /24 subnets out of it, one per availability zone."
  }
}
variable "vpc_name" {
  type        = string
  default     = "app-vpc"
  description = "Name tag of the VPC, as the _monolithic template tagged it"

  validation {
    condition     = length(var.vpc_name) > 0
    error_message = "vpc_name must not be empty."
  }
}
variable "availability_zone_a" {
  type        = string
  description = "First availability zone, as a full zone name. The root passes the same two zone names here and to the egress VPC, because the transit gateway keeps a flow in the zone it arrived in only when the destination attachment has a subnet in that zone - two VPCs in different zone pairs turn every flow into a cross-zone one (rules.md B-6)"

  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-[0-9][a-z]$", var.availability_zone_a))
    error_message = "availability_zone_a must be a full availability zone name (e.g. us-east-1a), not a suffix."
  }
}
variable "availability_zone_b" {
  type        = string
  description = "Second availability zone, as a full zone name"

  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-[0-9][a-z]$", var.availability_zone_b))
    error_message = "availability_zone_b must be a full availability zone name (e.g. us-east-1b), not a suffix."
  }
  validation {
    condition     = var.availability_zone_b != var.availability_zone_a
    error_message = "availability_zone_b must differ from availability_zone_a. A transit gateway VPC attachment takes at most one subnet per zone, so two subnets in one zone fail the attachment create with DuplicateSubnetsInSameZone."
  }
}
variable "enable_dns_support" {
  type        = bool
  default     = true
  description = <<-DESC
    Whether the Amazon-provided DNS resolver answers inside this VPC, as the _monolithic template set it.

    This one is not a formality in this project. The firewall policy drops DNS on port 53 in both
    protocols, so an instance here cannot use a public resolver - but the Amazon resolver at the VPC base
    address plus two is answered inside the VPC and matches the local route, so those queries never reach
    the transit gateway and never reach the firewall.

    Setting this false therefore does not make the demo stricter, it makes the instance unusable: name
    resolution would have to leave the VPC, the firewall would drop it, and dnf, the code-server download
    and the SSM agent's own registration would all fail with resolution errors.
  DESC
}
variable "enable_dns_hostnames" {
  type        = bool
  default     = true
  description = "Whether instances get DNS hostnames, as the _monolithic template set it. There is no internet gateway in this VPC, so no instance here has a public name to register whatever this is set to"
}
variable "private_subnet_name_prefix" {
  type        = string
  default     = "app-private-sn"
  description = "Name tag prefix of the two private subnets; the zone letter is appended, giving app-private-sn-a as the _monolithic template tagged it. Private in the strict sense - this VPC has no internet gateway, so the only path out of it is the transit gateway and therefore the firewall"

  validation {
    condition     = length(var.private_subnet_name_prefix) > 0
    error_message = "private_subnet_name_prefix must not be empty."
  }
}
variable "route_table_name" {
  type        = string
  default     = "app-rt"
  description = <<-DESC
    Name tag of the single route table shared by both private subnets, as the _monolithic template tagged
    it.

    One table for both zones is right here, unlike in the egress VPC. The only non-local route it carries
    is 0.0.0.0/0 to the transit gateway, and a transit gateway is not a zonal target - the gateway itself
    decides which zone's attachment ENI a flow uses. Splitting this per zone would add two resources and
    change nothing.
  DESC

  validation {
    condition     = length(var.route_table_name) > 0
    error_message = "route_table_name must not be empty."
  }
}
