variable "vpc_cidr_block" {
  type        = string
  default     = "10.101.0.0/16"
  description = "CIDR block for the VPC, as the _monolithic template had it"
  validation {
    condition     = can(cidrhost(var.vpc_cidr_block, 0))
    error_message = "vpc_cidr_block must be a valid IPv4 CIDR block (e.g. 10.101.0.0/16)."
  }
  validation {
    # Both subnets are carved out with cidrsubnet(..., 24 - prefix, n), so a prefix longer than /24 makes
    # newbits negative and the plan fails with a message that does not name this variable.
    condition     = tonumber(split("/", var.vpc_cidr_block)[1]) <= 24
    error_message = "vpc_cidr_block must be /24 or shorter, because each subnet is carved out of it as a /24."
  }
}
variable "enable_dns_support" {
  type        = bool
  default     = true
  description = "Whether the VPC provides DNS resolution through the Amazon-provided resolver. Required here: Fluent Bit resolves the regional CloudWatch Logs endpoint through it, and the ECS agent resolves the ECS and ECR endpoints"
}
variable "enable_dns_hostnames" {
  type        = bool
  default     = true
  description = "Whether instances launched in the VPC receive public DNS hostnames"
}
variable "vpc_name" {
  type        = string
  default     = "logging-vpc"
  description = "Name tag for the VPC, as the _monolithic template had it"
  validation {
    condition     = length(var.vpc_name) > 0
    error_message = "vpc_name must not be empty."
  }
}
variable "internet_gateway_name" {
  type        = string
  default     = "logging-igw"
  description = "Name tag for the internet gateway"
  validation {
    condition     = length(var.internet_gateway_name) > 0
    error_message = "internet_gateway_name must not be empty."
  }
}
variable "public_subnet_name" {
  type        = string
  default     = "logging-pub"
  description = "Base name tag for the public subnets, suffixed with the AZ letter (e.g. logging-pub-a), which is how the _monolithic template named them"
  validation {
    condition     = length(var.public_subnet_name) > 0
    error_message = "public_subnet_name must not be empty."
  }
}
variable "public_route_table_name" {
  type        = string
  default     = "logging-pub-rt"
  description = "Name tag for the public route table"
  validation {
    condition     = length(var.public_route_table_name) > 0
    error_message = "public_route_table_name must not be empty."
  }
}
variable "availability_zone_suffixes" {
  type        = list(string)
  default     = ["a", "b"]
  description = "The two AZ letters the public subnets are placed in, appended to the region name, which is where the _monolithic template placed them. Exactly two, because this module declares a named subnet per zone rather than generating them"
  validation {
    condition     = length(var.availability_zone_suffixes) == 2
    error_message = "availability_zone_suffixes must contain exactly two entries, because this module declares one public subnet per zone by name rather than by for_each."
  }
  validation {
    condition     = alltrue([for suffix in var.availability_zone_suffixes : can(regex("^[a-z]$", suffix))])
    error_message = "availability_zone_suffixes entries must each be a single lowercase letter (e.g. a), which is appended to the region name to form the zone."
  }
  validation {
    condition     = var.availability_zone_suffixes[0] != var.availability_zone_suffixes[1]
    error_message = "availability_zone_suffixes entries must differ. Two subnets in one zone leave the Auto Scaling group a single zone to place capacity in."
  }
}
