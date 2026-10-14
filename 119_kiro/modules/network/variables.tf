variable "vpc_cidr_block" {
  type        = string
  default     = "10.0.0.0/16"
  description = "IPv4 CIDR for the VPC; the first two /24 networks become the public NAT and private bootstrap subnets"

  validation {
    condition = (
      can(regex("^[0-9]{1,3}(\\.[0-9]{1,3}){3}/(1[6-9]|2[0-3])$", var.vpc_cidr_block)) &&
      can(cidrsubnet(var.vpc_cidr_block, 24 - tonumber(split("/", var.vpc_cidr_block)[1]), 1))
    )
    error_message = "vpc_cidr_block must be a valid IPv4 VPC CIDR from /16 through /23 so it can provide distinct public and private /24 subnets."
  }
}

variable "availability_zone" {
  type        = string
  description = "Availability zone shared by the public NAT subnet and private bootstrap subnet"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.availability_zone))
    error_message = "availability_zone must be a non-empty AWS availability-zone name such as us-east-1a."
  }
}

variable "vpc_name" {
  type        = string
  default     = "kiro-vpc"
  description = "Name tag for the VPC"

  validation {
    condition     = length(var.vpc_name) >= 1 && length(var.vpc_name) <= 256
    error_message = "vpc_name must be 1-256 characters."
  }
}

variable "internet_gateway_name" {
  type        = string
  default     = "kiro-igw"
  description = "Name tag for the internet gateway"

  validation {
    condition     = length(var.internet_gateway_name) >= 1 && length(var.internet_gateway_name) <= 256
    error_message = "internet_gateway_name must be 1-256 characters."
  }
}

variable "public_subnet_name" {
  type        = string
  default     = "kiro-public-subnet"
  description = "Name tag for the public subnet containing the NAT gateway"

  validation {
    condition     = length(var.public_subnet_name) >= 1 && length(var.public_subnet_name) <= 256
    error_message = "public_subnet_name must be 1-256 characters."
  }
}

variable "public_route_table_name" {
  type        = string
  default     = "kiro-public-rt"
  description = "Name tag for the public route table"

  validation {
    condition     = length(var.public_route_table_name) >= 1 && length(var.public_route_table_name) <= 256
    error_message = "public_route_table_name must be 1-256 characters."
  }
}

variable "private_subnet_name" {
  type        = string
  default     = "kiro-private-subnet"
  description = "Name tag for the private subnet containing the bootstrap instance"

  validation {
    condition     = length(var.private_subnet_name) >= 1 && length(var.private_subnet_name) <= 256
    error_message = "private_subnet_name must be 1-256 characters."
  }
}

variable "private_route_table_name" {
  type        = string
  default     = "kiro-private-rt"
  description = "Name tag for the private route table"

  validation {
    condition     = length(var.private_route_table_name) >= 1 && length(var.private_route_table_name) <= 256
    error_message = "private_route_table_name must be 1-256 characters."
  }
}

variable "nat_gateway_name" {
  type        = string
  default     = "kiro-nat"
  description = "Name tag for the public NAT gateway"

  validation {
    condition     = length(var.nat_gateway_name) >= 1 && length(var.nat_gateway_name) <= 256
    error_message = "nat_gateway_name must be 1-256 characters."
  }
}

variable "nat_eip_name" {
  type        = string
  default     = "kiro-nat-eip"
  description = "Name tag for the NAT gateway Elastic IP"

  validation {
    condition     = length(var.nat_eip_name) >= 1 && length(var.nat_eip_name) <= 256
    error_message = "nat_eip_name must be 1-256 characters."
  }
}
