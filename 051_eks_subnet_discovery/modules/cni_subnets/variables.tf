variable "vpc_id" {
  type        = string
  description = "VPC the secondary CIDR block is associated with and the discovered subnets are created in. Injected as an ID so this module never looks the network module's resources up itself (rules.md B-6)"

  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must be a valid VPC ID (e.g. vpc-0123456789abcdef0)."
  }
}
variable "secondary_cidr_block" {
  type        = string
  default     = "100.64.0.0/16"
  description = "CIDR block associated with the VPC as a secondary range, and carved into the discovered subnets. Defaults into 100.64.0.0/10, the CG-NAT range AWS recommends for exactly this purpose: it is not RFC 1918 space that might be needed for a peered VPC or an on-premises network, and it is not space that belongs to somebody else either. AWS also refuses a secondary block from a different RFC 1918 range than the primary, so 172.16.0.0/12 or 192.168.0.0/16 against a 10.0.0.0/8 VPC is rejected outright"

  validation {
    condition     = can(cidrhost(var.secondary_cidr_block, 0))
    error_message = "secondary_cidr_block must be a valid IPv4 CIDR block (e.g. 100.64.0.0/16)."
  }
  validation {
    condition     = tonumber(split("/", var.secondary_cidr_block)[1]) >= 16 && tonumber(split("/", var.secondary_cidr_block)[1]) <= 28
    error_message = "secondary_cidr_block must be between /16 and /28. AWS accepts VPC CIDR associations in that range only."
  }
}
variable "subnet_prefix_length" {
  type        = number
  default     = 24
  description = "Prefix length of each discovered subnet carved out of secondary_cidr_block. The whole point of these subnets is to have room the nodes' own subnets do not, so this is deliberately far more generous than the primary subnets: a /24 holds 251 usable addresses against a /28's 11"

  validation {
    condition     = var.subnet_prefix_length >= 16 && var.subnet_prefix_length <= 28
    error_message = "subnet_prefix_length must be between 16 and 28. AWS reserves five addresses in every subnet, so a /28 is the smallest a subnet can be."
  }
  validation {
    # Cross-variable, available since Terraform 1.9 (rules.md B-1). Neither value is
    # wrong on its own; the pair is what has to leave room for the subnets.
    condition     = var.subnet_prefix_length >= tonumber(split("/", var.secondary_cidr_block)[1])
    error_message = "subnet_prefix_length must be at least as long as secondary_cidr_block's own prefix length, or there is no room to carve subnets out of it. cidrsubnet would otherwise fail with a negative newbits during plan."
  }
}
variable "availability_zone_suffixes" {
  type        = list(string)
  default     = ["a", "b"]
  description = "AZ letters to create a discovered subnet in, one each, in order. These have to be the zones the worker nodes are in: the VPC CNI only considers tagged subnets in the same VPC and the same Availability Zone as the node, so a subnet in a zone with no nodes is discovered and never used, and a zone whose nodes have no tagged subnet gets no extra addresses at all"

  validation {
    condition     = length(var.availability_zone_suffixes) > 0
    error_message = "availability_zone_suffixes must contain at least one AZ letter."
  }
  validation {
    condition     = alltrue([for suffix in var.availability_zone_suffixes : can(regex("^[a-z]$", suffix))])
    error_message = "availability_zone_suffixes must contain single lowercase letters (e.g. [\"a\", \"b\"]), which are appended to the region name."
  }
  validation {
    condition     = length(distinct(var.availability_zone_suffixes)) == length(var.availability_zone_suffixes)
    error_message = "availability_zone_suffixes must not repeat a letter; each zone gets exactly one discovered subnet."
  }
}
variable "nat_gateway_ids" {
  type        = map(string)
  description = "NAT Gateway ID to route each discovered subnet's outbound traffic through, keyed by the AZ letter of the subnet that uses it. A map rather than a list because these IDs come from another module's output and are unknown until apply, while for_each needs keys that are known during plan (rules.md B-8)"

  validation {
    condition     = alltrue([for key in keys(var.nat_gateway_ids) : can(regex("^[a-z]$", key))])
    error_message = "nat_gateway_ids must be keyed by single lowercase AZ letters, matching availability_zone_suffixes."
  }
  validation {
    # Keys are literal strings in the caller's configuration, so this runs during plan
    # even while the IDs themselves are still unknown (rules.md B-8). Without it a
    # missing zone surfaces during apply as a plain "key does not exist" on a map
    # lookup, several minutes in.
    condition     = alltrue([for suffix in var.availability_zone_suffixes : contains(keys(var.nat_gateway_ids), suffix)])
    error_message = "nat_gateway_ids must contain an entry for every letter in availability_zone_suffixes. A discovered subnet with no route to a NAT gateway still hands out addresses, and the pods that get them cannot pull an image."
  }
  validation {
    condition     = alltrue([for id in values(var.nat_gateway_ids) : can(regex("^nat-[0-9a-f]+$", id))])
    error_message = "nat_gateway_ids must contain valid NAT Gateway IDs (e.g. nat-0123456789abcdef0)."
  }
}
variable "discovery_tag_key" {
  type        = string
  default     = "kubernetes.io/role/cni"
  description = "Tag key the VPC CNI filters on when it looks for subnets to allocate pod addresses from. This exact string is what the feature is: the CNI reads it and nothing validates it, so a typo here produces subnets that exist, route correctly and are never used - and the only symptom is pods still failing to get addresses"

  validation {
    condition     = length(var.discovery_tag_key) > 0 && length(var.discovery_tag_key) <= 128
    error_message = "discovery_tag_key must be 1-128 characters."
  }
  validation {
    condition     = !startswith(lower(var.discovery_tag_key), "aws:")
    error_message = "discovery_tag_key must not use the reserved \"aws:\" prefix, which EC2 rejects on CreateTags."
  }
}
variable "discovery_tag_value" {
  type        = string
  default     = "1"
  description = "Value for discovery_tag_key. The CNI only tests that the tag is present, so the value is conventional rather than meaningful - 1 is what the AWS documentation uses"

  validation {
    condition     = length(var.discovery_tag_value) <= 256
    error_message = "discovery_tag_value must be 256 characters or fewer."
  }
}
variable "subnet_name" {
  type        = string
  default     = "stem-cni"
  description = "Base Name tag for the discovered subnets, suffixed with the AZ letter (e.g. stem-cni-a)"

  validation {
    condition     = length(var.subnet_name) > 0
    error_message = "subnet_name must not be empty."
  }
}
variable "route_table_name" {
  type        = string
  default     = "stem-cni-rt"
  description = "Base Name tag for the per-AZ route tables of the discovered subnets, suffixed with the AZ letter"

  validation {
    condition     = length(var.route_table_name) > 0
    error_message = "route_table_name must not be empty."
  }
}
