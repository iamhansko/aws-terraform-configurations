variable "vpc_cidr_block" {
  type        = string
  default     = "10.0.0.0/16"
  description = "CIDR block for the VPC"

  validation {
    condition     = can(cidrhost(var.vpc_cidr_block, 0))
    error_message = "vpc_cidr_block must be a valid IPv4 CIDR block (e.g. 10.0.0.0/16)."
  }
}
variable "subnet_prefix_length" {
  type        = number
  default     = 24
  description = "Prefix length of each of the four subnets carved out of vpc_cidr_block. 24 gives 251 usable addresses per subnet, which is what every other project in this repository wants. This project passes 28 - 11 usable - on purpose: worker nodes have to run out of addresses in their own subnet before the VPC CNI has any reason to look for another one, so a roomy subnet would make the demo show nothing at all"

  validation {
    condition     = var.subnet_prefix_length >= 16 && var.subnet_prefix_length <= 28
    error_message = "subnet_prefix_length must be between 16 and 28. AWS reserves five addresses in every subnet, so a /28 is the smallest a subnet can be."
  }
  validation {
    # Cross-variable, available since Terraform 1.9 (rules.md B-1). Checking each
    # value alone cannot express this: the pair is what has to be consistent.
    condition     = var.subnet_prefix_length > tonumber(split("/", var.vpc_cidr_block)[1])
    error_message = "subnet_prefix_length must be longer than the VPC's own prefix length, or there is no room to carve subnets out of it. cidrsubnet would otherwise fail with a negative newbits during plan."
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
