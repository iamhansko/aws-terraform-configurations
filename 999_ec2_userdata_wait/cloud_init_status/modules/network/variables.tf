variable "vpc_cidr_block" {
  type        = string
  default     = "10.0.0.0/16"
  description = "CIDR block for the VPC"

  validation {
    condition     = can(cidrhost(var.vpc_cidr_block, 0))
    error_message = "vpc_cidr_block must be a valid IPv4 CIDR block (e.g. 10.0.0.0/16)."
  }
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

variable "public_subnet_name" {
  type        = string
  default     = "stem-public"
  description = "Base name tag for public subnets"

  validation {
    condition     = length(var.public_subnet_name) > 0
    error_message = "public_subnet_name must not be empty."
  }
}

variable "private_subnet_name" {
  type        = string
  default     = "stem-private"
  description = "Base name tag for private subnets"

  validation {
    condition     = length(var.private_subnet_name) > 0
    error_message = "private_subnet_name must not be empty."
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

variable "nat_gateway_name" {
  type        = string
  default     = "stem-natgw"
  description = "Base name tag for NAT Gateways"

  validation {
    condition     = length(var.nat_gateway_name) > 0
    error_message = "nat_gateway_name must not be empty."
  }
}
