variable "vpc_cidr_block" {
  type        = string
  default     = "10.0.0.0/16"
  description = "CIDR block for the VPC, as the _monolithic template had it. The public subnet is its first /24"

  validation {
    condition     = can(cidrhost(var.vpc_cidr_block, 0)) && tonumber(split("/", var.vpc_cidr_block)[1]) <= 24
    error_message = "vpc_cidr_block must be a valid IPv4 CIDR block of /24 or shorter, because the subnet is carved out of it as a /24."
  }
}
variable "availability_zone_suffix" {
  type        = string
  default     = "a"
  description = "AZ letter the public subnet is placed in, appended to the region name, as the _monolithic template had it"

  validation {
    condition     = can(regex("^[a-z]$", var.availability_zone_suffix))
    error_message = "availability_zone_suffix must be a single lowercase letter."
  }
}
variable "vpc_name" {
  type        = string
  default     = "vpc"
  description = "Name tag for the VPC, as the _monolithic template had it"

  validation {
    condition     = length(var.vpc_name) > 0
    error_message = "vpc_name must not be empty."
  }
}
variable "internet_gateway_name" {
  type        = string
  default     = "igw"
  description = "Name tag for the internet gateway"

  validation {
    condition     = length(var.internet_gateway_name) > 0
    error_message = "internet_gateway_name must not be empty."
  }
}
variable "public_subnet_name" {
  type        = string
  default     = "public-subnet-a"
  description = "Name tag for the public subnet, as the _monolithic template named the one it used"

  validation {
    condition     = length(var.public_subnet_name) > 0
    error_message = "public_subnet_name must not be empty."
  }
}
variable "public_route_table_name" {
  type        = string
  default     = "public-rt"
  description = "Name tag for the public route table"

  validation {
    condition     = length(var.public_route_table_name) > 0
    error_message = "public_route_table_name must not be empty."
  }
}
