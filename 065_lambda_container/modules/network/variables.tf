variable "region" {
  type        = string
  description = "Region the subnet is placed in, combined with availability_zone_suffix to name its zone. Passed in rather than read with a data source, so this module declares none"
  validation {
    condition     = can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]$", var.region))
    error_message = "region must be a region code such as ap-northeast-2."
  }
}
variable "vpc_cidr_block" {
  type        = string
  description = "CIDR block of the VPC"
  validation {
    condition     = can(cidrhost(var.vpc_cidr_block, 0))
    error_message = "vpc_cidr_block must be a valid IPv4 CIDR block (e.g. 10.0.0.0/16)."
  }
}
variable "public_subnet_cidr_block" {
  type        = string
  description = "CIDR block of the public subnet. Has to fall inside vpc_cidr_block, which EC2 enforces at CreateSubnet"
  validation {
    condition     = can(cidrhost(var.public_subnet_cidr_block, 0))
    error_message = "public_subnet_cidr_block must be a valid IPv4 CIDR block (e.g. 10.0.0.0/24)."
  }
}
variable "availability_zone_suffix" {
  type        = string
  default     = "a"
  description = "Letter appended to the region to name the subnet's zone. \"a\" as the _monolithic template hard-coded it"
  validation {
    condition     = can(regex("^[a-z]$", var.availability_zone_suffix))
    error_message = "availability_zone_suffix must be a single lowercase letter (e.g. a)."
  }
}
variable "vpc_name" {
  type        = string
  description = "Name tag of the VPC"
  validation {
    condition     = length(var.vpc_name) > 0
    error_message = "vpc_name must not be empty."
  }
}
variable "internet_gateway_name" {
  type        = string
  description = "Name tag of the internet gateway"
  validation {
    condition     = length(var.internet_gateway_name) > 0
    error_message = "internet_gateway_name must not be empty."
  }
}
variable "public_subnet_name" {
  type        = string
  description = "Name tag of the public subnet"
  validation {
    condition     = length(var.public_subnet_name) > 0
    error_message = "public_subnet_name must not be empty."
  }
}
variable "public_route_table_name" {
  type        = string
  description = "Name tag of the public route table"
  validation {
    condition     = length(var.public_route_table_name) > 0
    error_message = "public_route_table_name must not be empty."
  }
}
