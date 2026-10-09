variable "name" {
  type        = string
  default     = "egress"
  description = "Prefix for every Name tag in this VPC. The _monolithic template tagged these resources egress-vpc, egress-public-sn-a, egress-peering-sn-a, egress-firewall-sn-a, egress-igw, egress-public-rt, egress-natgw-a and egress-priv-rt-a; the tags here are derived from this prefix instead, so renaming the project renames all of them at once"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.name))
    error_message = "name must be lowercase letters, digits or hyphens and must not start or end with a hyphen."
  }
}
variable "region" {
  type        = string
  description = "Region name, prefixed to each zone suffix to form an availability zone name. Passed in rather than read from a data source in this module: a module carrying depends_on has every data source in it deferred to apply, and the zone names are more useful known at plan (rules.md D-6/I-3)"

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.region))
    error_message = "region must look like an AWS region (e.g. ap-northeast-2)."
  }
}
variable "availability_zone_suffixes" {
  type        = list(string)
  description = "Zone suffixes this VPC spans. These are the for_each keys for the subnets, NAT gateways and per-zone route tables, so they must be configuration literals (rules.md B-8)"

  validation {
    condition     = length(var.availability_zone_suffixes) >= 2
    error_message = "availability_zone_suffixes must name at least two zones; one NAT gateway is one zone's worth of egress for both VPCs."
  }
  validation {
    condition     = alltrue([for suffix in var.availability_zone_suffixes : can(regex("^[a-z]$", suffix))])
    error_message = "each availability_zone_suffixes entry must be a single lowercase letter."
  }
}
variable "vpc_cidr_block" {
  type        = string
  description = "Primary CIDR block of the egress VPC"

  validation {
    condition     = can(cidrhost(var.vpc_cidr_block, 0))
    error_message = "vpc_cidr_block must be a valid IPv4 CIDR block."
  }
}
variable "public_subnet_cidr_blocks" {
  type        = map(string)
  description = "Public subnet CIDR blocks by zone suffix. These hold the NAT gateways and are the only subnets in this project with a route to an internet gateway"

  validation {
    condition     = alltrue([for cidr in values(var.public_subnet_cidr_blocks) : can(cidrhost(cidr, 0))])
    error_message = "every public_subnet_cidr_blocks value must be a valid IPv4 CIDR block."
  }
  validation {
    condition     = alltrue([for suffix in var.availability_zone_suffixes : contains(keys(var.public_subnet_cidr_blocks), suffix)])
    error_message = "public_subnet_cidr_blocks must have an entry for every suffix in availability_zone_suffixes, or the subnet resource's for_each fails the plan with Invalid index."
  }
}
variable "attachment_subnet_cidr_blocks" {
  type        = map(string)
  description = "CIDR blocks by zone suffix for the subnets holding the transit gateway attachment's ENIs. Named for what they contain; the _monolithic template called them peering subnets, and nothing in this project peers"

  validation {
    condition     = alltrue([for cidr in values(var.attachment_subnet_cidr_blocks) : can(cidrhost(cidr, 0))])
    error_message = "every attachment_subnet_cidr_blocks value must be a valid IPv4 CIDR block."
  }
  validation {
    condition     = alltrue([for suffix in var.availability_zone_suffixes : contains(keys(var.attachment_subnet_cidr_blocks), suffix)])
    error_message = "attachment_subnet_cidr_blocks must have an entry for every suffix in availability_zone_suffixes."
  }
}
variable "firewall_subnet_cidr_blocks" {
  type        = map(string)
  description = "CIDR blocks by zone suffix for the subnets holding the Network Firewall endpoints. A firewall subnet carries nothing else - AWS places only the endpoint there - and gets no route table association in this module, which is deliberate and documented in modules/network_firewall/main.tf"

  validation {
    condition     = alltrue([for cidr in values(var.firewall_subnet_cidr_blocks) : can(cidrhost(cidr, 0))])
    error_message = "every firewall_subnet_cidr_blocks value must be a valid IPv4 CIDR block."
  }
  validation {
    condition     = alltrue([for suffix in var.availability_zone_suffixes : contains(keys(var.firewall_subnet_cidr_blocks), suffix)])
    error_message = "firewall_subnet_cidr_blocks must have an entry for every suffix in availability_zone_suffixes."
  }
}
variable "default_route_cidr_block" {
  type        = string
  default     = "0.0.0.0/0"
  description = "Destination of the two 'everything else' routes this module writes: the public route table's route to the internet gateway, and each attachment subnet's route to its zone's NAT gateway"

  validation {
    condition     = can(cidrhost(var.default_route_cidr_block, 0))
    error_message = "default_route_cidr_block must be a valid IPv4 CIDR block."
  }
}
