variable "vpc_cidr_block" {
  type        = string
  default     = "10.1.0.0/16"
  description = "CIDR block for the VPC. Carved into /24 subnets, so a prefix longer than /24 leaves nothing to carve"

  validation {
    condition     = can(cidrhost(var.vpc_cidr_block, 0))
    error_message = "vpc_cidr_block must be a valid IPv4 CIDR block (e.g. 10.1.0.0/16)."
  }

  # The module derives four /24s from this block, so the VPC prefix has to leave
  # at least two bits to carve with. A /24 or longer would make cidrsubnet fail
  # during apply with "prefix extension of ... does not accommodate a subnet
  # numbered ...", which is a worse place to find out than plan.
  validation {
    condition     = tonumber(split("/", var.vpc_cidr_block)[1]) <= 22
    error_message = "vpc_cidr_block must be /22 or shorter, because the module carves four /24 subnets out of it."
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
  default     = "wsi-vpc"
  description = "Name tag for the VPC"

  validation {
    condition     = length(var.vpc_name) > 0
    error_message = "vpc_name must not be empty."
  }
}
variable "internet_gateway_name" {
  type        = string
  default     = "wsi-igw"
  description = "Name tag for the Internet Gateway"

  validation {
    condition     = length(var.internet_gateway_name) > 0
    error_message = "internet_gateway_name must not be empty."
  }
}
variable "public_subnet_name" {
  type        = string
  default     = "wsi-public"
  description = "Base name tag for public subnets, suffixed with the AZ letter (e.g. wsi-public-a)"

  validation {
    condition     = length(var.public_subnet_name) > 0
    error_message = "public_subnet_name must not be empty."
  }
}
variable "private_subnet_name" {
  type        = string
  default     = "wsi-private"
  description = "Base name tag for private subnets, suffixed with the AZ letter (e.g. wsi-private-a)"

  validation {
    condition     = length(var.private_subnet_name) > 0
    error_message = "private_subnet_name must not be empty."
  }
}
variable "public_route_table_name" {
  type        = string
  default     = "wsi-public-rt"
  description = "Name tag for the shared public route table"

  validation {
    condition     = length(var.public_route_table_name) > 0
    error_message = "public_route_table_name must not be empty."
  }
}
variable "private_route_table_name" {
  type        = string
  default     = "wsi-private-rt"
  description = "Base name tag for the per-AZ private route tables, suffixed with the AZ letter"

  validation {
    condition     = length(var.private_route_table_name) > 0
    error_message = "private_route_table_name must not be empty."
  }
}
variable "nat_gateway_name" {
  type        = string
  default     = "wsi-natgw"
  description = "Base name tag for the per-AZ NAT Gateways, suffixed with the AZ letter"

  validation {
    condition     = length(var.nat_gateway_name) > 0
    error_message = "nat_gateway_name must not be empty."
  }
}
variable "map_public_ip_on_launch" {
  type        = bool
  default     = true
  description = "Whether instances launched into the public subnets get a public IPv4 address without asking for one. This is the only thing that distinguishes these subnets from the private ones besides their route table, and nothing in this project launches an instance to exercise it"
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
