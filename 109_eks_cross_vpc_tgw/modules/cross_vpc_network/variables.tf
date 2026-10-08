variable "region" {
  type        = string
  description = "Region the availability zone suffixes are appended to"

  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]$", var.region))
    error_message = "region must be a valid AWS region name (e.g. ap-northeast-2)."
  }
}

variable "name" {
  type        = string
  description = "Prefix for every Name tag in this VPC, and what distinguishes the two copies of this module from each other"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,30}[a-z0-9]$", var.name))
    error_message = "name must be 3-32 lowercase letters, digits or hyphens and must not start or end with a hyphen."
  }
}

variable "vpc_cidr_block" {
  type        = string
  description = "Primary CIDR block. Routable across the transit gateway, so the two VPCs' primary blocks must not overlap"

  validation {
    condition     = can(cidrhost(var.vpc_cidr_block, 0))
    error_message = "vpc_cidr_block must be a valid IPv4 CIDR block."
  }
}

variable "secondary_cidr_block" {
  type        = string
  default     = "100.64.0.0/16"
  description = "Non-routable CIDR attached as a secondary block, which the cluster and node tiers come out of. Both VPCs use the same block on purpose - that is what makes it non-routable, and what the private NAT gateway exists to translate"

  validation {
    condition     = can(cidrhost(var.secondary_cidr_block, 0))
    error_message = "secondary_cidr_block must be a valid IPv4 CIDR block."
  }
}

variable "availability_zone_suffixes" {
  type        = list(string)
  default     = ["a", "c"]
  description = "Availability zones this VPC spans, by suffix. Two - a and c - exactly the pair the _monolithic template's AzMapping defined. Every tier gets a subnet in each, and the private and node tiers get a NAT gateway and a route table per zone"

  validation {
    condition     = length(var.availability_zone_suffixes) >= 2
    error_message = "availability_zone_suffixes must name at least two zones; an EKS control plane requires subnets in two, and so does an ALB."
  }
}

variable "public_subnet_cidr_blocks" {
  type        = map(string)
  description = "Public subnet CIDR per zone suffix, out of the primary block. Holds the workbench, the ALB and the public NAT gateway"

  validation {
    condition     = alltrue([for cidr in values(var.public_subnet_cidr_blocks) : can(cidrhost(cidr, 0))])
    error_message = "public_subnet_cidr_blocks values must be valid IPv4 CIDR blocks."
  }
}

variable "private_subnet_cidr_blocks" {
  type        = map(string)
  description = "Private subnet CIDR per zone suffix, out of the primary block. Holds the private NAT gateway and the transit gateway attachment - the attachment has to be in a routable subnet, because the other VPC has to address it"

  validation {
    condition     = alltrue([for cidr in values(var.private_subnet_cidr_blocks) : can(cidrhost(cidr, 0))])
    error_message = "private_subnet_cidr_blocks values must be valid IPv4 CIDR blocks."
  }
}

variable "cluster_subnet_cidr_blocks" {
  type        = map(string)
  description = "Cluster subnet CIDR per zone suffix, out of the secondary block. Only the EKS control plane's cross-account ENIs go here, which is why a /28 is enough and why the tier needs no route off the VPC"

  validation {
    condition     = alltrue([for cidr in values(var.cluster_subnet_cidr_blocks) : can(cidrhost(cidr, 0))])
    error_message = "cluster_subnet_cidr_blocks values must be valid IPv4 CIDR blocks."
  }
}

variable "node_subnet_cidr_blocks" {
  type        = map(string)
  description = "Node subnet CIDR per zone suffix, out of the secondary block. The nodes and every pod address come from here, which is the reason the secondary block exists - a /20 per zone is 4096 addresses that cost nothing routable"

  validation {
    condition     = alltrue([for cidr in values(var.node_subnet_cidr_blocks) : can(cidrhost(cidr, 0))])
    error_message = "node_subnet_cidr_blocks values must be valid IPv4 CIDR blocks."
  }
}

variable "peer_cidr_blocks" {
  type        = list(string)
  description = "CIDRs reachable through the transit gateway - the other VPC's primary block. Configuration values rather than the other module's output, which is what keeps two copies of this module from depending on each other"

  validation {
    condition     = alltrue([for cidr in var.peer_cidr_blocks : can(cidrhost(cidr, 0))])
    error_message = "peer_cidr_blocks must contain valid IPv4 CIDR blocks."
  }
}

variable "transit_gateway_id" {
  type        = string
  description = "Transit gateway the peer routes point at (rules.md B-6)"

  validation {
    condition     = can(regex("^tgw-[0-9a-f]+$", var.transit_gateway_id))
    error_message = "transit_gateway_id must be a valid transit gateway ID (e.g. tgw-0123456789abcdef0)."
  }
}

variable "transit_gateway_attachment_dependency" {
  type        = any
  default     = null
  description = "Anything that has to exist before a route may point at the transit gateway - in practice this VPC's attachment. A route created before the attachment is accepted and then blackholes, which is not an error anywhere (rules.md D-2)"
}

variable "public_subnet_tags" {
  type        = map(string)
  default     = {}
  description = "Tags merged into the public subnets. kubernetes.io/role/elb belongs here: the AWS Load Balancer Controller discovers subnets by tag, and an internet-facing scheme with no tagged public subnet fails with \"couldn't auto-discover subnets\" (rules.md G-1)"

  validation {
    condition     = alltrue([for key in keys(var.public_subnet_tags) : length(key) > 0 && !startswith(lower(key), "aws:")])
    error_message = "public_subnet_tags keys must be non-empty and must not use the reserved \"aws:\" prefix."
  }
}

variable "private_subnet_tags" {
  type        = map(string)
  default     = {}
  description = "Tags merged into the private subnets"

  validation {
    condition     = alltrue([for key in keys(var.private_subnet_tags) : length(key) > 0 && !startswith(lower(key), "aws:")])
    error_message = "private_subnet_tags keys must be non-empty and must not use the reserved \"aws:\" prefix."
  }
}

variable "cluster_subnet_tags" {
  type        = map(string)
  default     = {}
  description = "Tags merged into the cluster subnets. Deliberately not tagged for load balancer discovery: an ALB placed here would be unreachable, since the tier has no route off the VPC"

  validation {
    condition     = alltrue([for key in keys(var.cluster_subnet_tags) : length(key) > 0 && !startswith(lower(key), "aws:")])
    error_message = "cluster_subnet_tags keys must be non-empty and must not use the reserved \"aws:\" prefix."
  }
}

variable "node_subnet_tags" {
  type        = map(string)
  default     = {}
  description = "Tags merged into the node subnets. Not tagged for load balancer discovery either - target-type ip sends traffic to pod addresses in this tier, but the load balancer itself belongs in the public one"

  validation {
    condition     = alltrue([for key in keys(var.node_subnet_tags) : length(key) > 0 && !startswith(lower(key), "aws:")])
    error_message = "node_subnet_tags keys must be non-empty and must not use the reserved \"aws:\" prefix."
  }
}
