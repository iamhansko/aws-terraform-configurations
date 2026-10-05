variable "vpc_cidr_block" {
  type        = string
  default     = "10.0.0.0/16"
  description = "CIDR block for the VPC"

  validation {
    condition     = can(cidrhost(var.vpc_cidr_block, 0))
    error_message = "vpc_cidr_block must be a valid IPv4 CIDR block (e.g. 10.0.0.0/16)."
  }
}
variable "enable_dns_support" {
  type        = bool
  default     = true
  description = "Whether the VPC provides DNS resolution through the Amazon-provided resolver"
}
variable "enable_dns_hostnames" {
  type        = bool
  default     = true
  description = "Whether instances launched in the VPC receive public DNS hostnames"
}
variable "vpc_name" {
  type        = string
  default     = "stem-vpc"
  description = "Name tag for the VPC"

  validation {
    condition     = length(var.vpc_name) > 0
    error_message = "vpc_name must not be empty."
  }
}
variable "internet_gateway_name" {
  type        = string
  default     = "stem-igw"
  description = "Name tag for the Internet Gateway"

  validation {
    condition     = length(var.internet_gateway_name) > 0
    error_message = "internet_gateway_name must not be empty."
  }
}
variable "public_subnet_name" {
  type        = string
  default     = "stem-public"
  description = "Base name tag for public subnets, suffixed with the AZ letter (e.g. stem-public-a)"

  validation {
    condition     = length(var.public_subnet_name) > 0
    error_message = "public_subnet_name must not be empty."
  }
}
variable "private_subnet_name" {
  type        = string
  default     = "stem-private"
  description = "Base name tag for private subnets, suffixed with the AZ letter (e.g. stem-private-a)"

  validation {
    condition     = length(var.private_subnet_name) > 0
    error_message = "private_subnet_name must not be empty."
  }
}
variable "public_route_table_name" {
  type        = string
  default     = "stem-public-rt"
  description = "Name tag for the shared public route table"

  validation {
    condition     = length(var.public_route_table_name) > 0
    error_message = "public_route_table_name must not be empty."
  }
}
variable "private_route_table_name" {
  type        = string
  default     = "stem-private-rt"
  description = "Base name tag for the per-AZ private route tables, suffixed with the AZ letter"

  validation {
    condition     = length(var.private_route_table_name) > 0
    error_message = "private_route_table_name must not be empty."
  }
}
variable "nat_gateway_name" {
  type        = string
  default     = "stem-natgw"
  description = "Base name tag for the per-AZ NAT Gateways, suffixed with the AZ letter"

  validation {
    condition     = length(var.nat_gateway_name) > 0
    error_message = "nat_gateway_name must not be empty."
  }
}
variable "public_subnet_tags" {
  type        = map(string)
  default     = {}
  description = "Tags merged into every public subnet, on top of its Name tag. Empty by default, unlike the EKS projects in this repository: the kubernetes.io/role/elb tag they default to exists only so the AWS Load Balancer Controller can auto-discover subnets, and there is no cluster here to discover them"

  validation {
    condition     = alltrue([for key in keys(var.public_subnet_tags) : length(key) > 0])
    error_message = "public_subnet_tags must not contain empty tag keys."
  }
}
variable "private_subnet_tags" {
  type        = map(string)
  default     = {}
  description = "Tags merged into every private subnet, on top of its Name tag. Empty by default for the same reason as public_subnet_tags"

  validation {
    condition     = alltrue([for key in keys(var.private_subnet_tags) : length(key) > 0])
    error_message = "private_subnet_tags must not contain empty tag keys."
  }
}
variable "multus_subnet_name" {
  type        = string
  default     = "multus"
  description = "Name tag prefix for the subnet the Multus attachment draws pod addresses from. A subnet of its own rather than the node's, so the addresses host-local hands out are not shared with the VPC CNI and the link route ipvlan installs on a pod's net1 covers only the Multus network"

  validation {
    condition     = length(var.multus_subnet_name) > 0
    error_message = "multus_subnet_name must not be empty."
  }
}
variable "multus_pod_range_newbits" {
  type        = number
  default     = 1
  description = "How many bits to add to the Multus subnet's prefix to carve out the block host-local hands addresses from. One, so the upper half of the subnet goes to pods and the lower half is left for the primary addresses of the ENIs the nodes attach there - which the VPC assigns and this configuration cannot choose"

  validation {
    condition     = var.multus_pod_range_newbits >= 1 && var.multus_pod_range_newbits <= 8
    error_message = "multus_pod_range_newbits must be between 1 and 8. At least one, because the ENIs the nodes attach in this subnet need addresses outside the block host-local hands out."
  }
}
variable "multus_pod_range_index" {
  type        = number
  default     = 1
  description = "Which of the blocks multus_pod_range_newbits produces to hand to pods, counting from zero. One with newbits at one means the upper half, leaving the ENI addresses at the bottom of the subnet"

  validation {
    condition     = var.multus_pod_range_index >= 0
    error_message = "multus_pod_range_index must be zero or greater."
  }
  validation {
    # The pair is what can be wrong, not either number alone (rules.md B-1).
    condition     = var.multus_pod_range_index < pow(2, var.multus_pod_range_newbits)
    error_message = "multus_pod_range_index must be less than 2 ^ multus_pod_range_newbits - there are only that many blocks to choose from."
  }
}
