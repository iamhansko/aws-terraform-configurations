variable "vpc_cidr_block" {
  type        = string
  description = "CIDR block for the workbench VPC; the first /24 is used for its public subnet."

  validation {
    condition     = can(cidrhost(var.vpc_cidr_block, 0)) && tonumber(split("/", var.vpc_cidr_block)[1]) <= 24
    error_message = "vpc_cidr_block must be a valid IPv4 CIDR of /24 or shorter."
  }
}

variable "availability_zone_suffix" {
  type        = string
  description = "Availability-zone suffix appended to the current provider region."

  validation {
    condition     = can(regex("^[a-z]$", var.availability_zone_suffix))
    error_message = "availability_zone_suffix must be one lowercase letter."
  }
}

variable "vpc_name" {
  type        = string
  description = "Name tag for the VPC."

  validation {
    condition     = length(trimspace(var.vpc_name)) > 0 && length(var.vpc_name) <= 255
    error_message = "vpc_name must be 1-255 characters and not blank."
  }
}

variable "internet_gateway_name" {
  type        = string
  description = "Name tag for the internet gateway."

  validation {
    condition     = length(trimspace(var.internet_gateway_name)) > 0 && length(var.internet_gateway_name) <= 255
    error_message = "internet_gateway_name must be 1-255 characters and not blank."
  }
}

variable "public_subnet_name" {
  type        = string
  description = "Base Name tag for the public subnet."

  validation {
    condition     = length(trimspace(var.public_subnet_name)) > 0 && length(var.public_subnet_name) <= 253
    error_message = "public_subnet_name must be 1-253 characters and not blank."
  }
}

variable "public_route_table_name" {
  type        = string
  description = "Name tag for the public route table."

  validation {
    condition     = length(trimspace(var.public_route_table_name)) > 0 && length(var.public_route_table_name) <= 255
    error_message = "public_route_table_name must be 1-255 characters and not blank."
  }
}
