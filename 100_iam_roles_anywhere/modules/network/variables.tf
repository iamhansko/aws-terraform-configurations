variable "vpc_cidr_block" {
  type        = string
  default     = "10.0.0.0/16"
  description = "CIDR block for the VPC, as the _monolithic template had it"

  validation {
    condition     = can(cidrhost(var.vpc_cidr_block, 0))
    error_message = "vpc_cidr_block must be a valid IPv4 CIDR block (e.g. 10.0.0.0/16)."
  }
  validation {
    # The subnet is carved out with cidrsubnet(..., 24 - prefix, 0), so a prefix longer than /24
    # makes newbits negative and the call fails during plan with an error about the prefix
    # extension that does not name this variable.
    condition     = tonumber(split("/", var.vpc_cidr_block)[1]) <= 24
    error_message = "vpc_cidr_block must be /24 or shorter, because the public subnet is carved out of it as a /24."
  }
}
variable "enable_dns_support" {
  type        = bool
  default     = true
  description = "Whether the VPC provides DNS resolution through the Amazon-provided resolver. True is required here: the instance resolves acm.<region>.amazonaws.com, s3.<region>.amazonaws.com and the SSM endpoints during cloud-init, and resolves nothing if this is off"
}
variable "enable_dns_hostnames" {
  type        = bool
  default     = true
  description = "Whether instances launched in the VPC receive public DNS hostnames"
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
  description = "Name tag for the internet gateway, as the _monolithic template had it"

  validation {
    condition     = length(var.internet_gateway_name) > 0
    error_message = "internet_gateway_name must not be empty."
  }
}
variable "public_subnet_name" {
  type        = string
  default     = "public-subnet"
  description = "Name tag for the public subnet, as the _monolithic template had it. No availability zone suffix, because there is only one subnet - see main.tf for why"

  validation {
    condition     = length(var.public_subnet_name) > 0
    error_message = "public_subnet_name must not be empty."
  }
}
variable "public_route_table_name" {
  type        = string
  default     = "public-rt"
  description = "Name tag for the public route table, as the _monolithic template had it"

  validation {
    condition     = length(var.public_route_table_name) > 0
    error_message = "public_route_table_name must not be empty."
  }
}
