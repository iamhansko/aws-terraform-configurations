variable "vpc_cidr_block" {
  type        = string
  default     = "10.10.0.0/16"
  description = "CIDR block for the VPC"

  validation {
    condition     = can(cidrhost(var.vpc_cidr_block, 0))
    error_message = "vpc_cidr_block must be a valid IPv4 CIDR block (e.g. 10.10.0.0/16)."
  }
}
variable "public_subnet_a_cidr_block" {
  type        = string
  default     = "10.10.0.0/24"
  description = "CIDR block of the public subnet in the first zone"

  validation {
    condition     = can(cidrhost(var.public_subnet_a_cidr_block, 0))
    error_message = "public_subnet_a_cidr_block must be a valid IPv4 CIDR block (e.g. 10.10.0.0/24)."
  }
}
variable "public_subnet_c_cidr_block" {
  type        = string
  default     = "10.10.1.0/24"
  description = "CIDR block of the public subnet in the second zone"

  validation {
    condition     = can(cidrhost(var.public_subnet_c_cidr_block, 0))
    error_message = "public_subnet_c_cidr_block must be a valid IPv4 CIDR block (e.g. 10.10.1.0/24)."
  }

  validation {
    # The two subnets would otherwise be created with the same addresses, which EC2 rejects at
    # CreateSubnet with InvalidSubnet.Conflict - after the VPC and the gateway already exist.
    condition     = var.public_subnet_c_cidr_block != var.public_subnet_a_cidr_block
    error_message = "public_subnet_c_cidr_block must differ from public_subnet_a_cidr_block."
  }
}
variable "availability_zone_suffixes" {
  type        = list(string)
  default     = ["a", "c"]
  description = "The two AZ letters the public subnets are placed in, appended to the region name. Exactly two, because this module declares one named subnet per zone rather than generating them"

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
    error_message = "availability_zone_suffixes entries must differ. An internet-facing ALB is rejected with fewer than two distinct zones."
  }
}
variable "enable_dns_support" {
  type        = bool
  default     = true
  description = "Whether the VPC resolves names through the Amazon-provided resolver. Required here: a Fargate task resolves the ECR and CloudWatch Logs endpoints through it before its container starts"
}
variable "enable_dns_hostnames" {
  type        = bool
  default     = true
  description = "Whether instances launched in the VPC receive public DNS hostnames"
}
variable "vpc_name" {
  type        = string
  default     = "mo-vpc"
  description = "Name tag for the VPC"

  validation {
    condition     = length(var.vpc_name) > 0
    error_message = "vpc_name must not be empty."
  }
}
variable "internet_gateway_name" {
  type        = string
  default     = "mo-igw"
  description = "Name tag for the internet gateway"

  validation {
    condition     = length(var.internet_gateway_name) > 0
    error_message = "internet_gateway_name must not be empty."
  }
}
variable "public_subnet_name" {
  type        = string
  default     = "mo-public"
  description = "Base name tag for the public subnets, suffixed with the AZ letter (e.g. mo-public-a)"

  validation {
    condition     = length(var.public_subnet_name) > 0
    error_message = "public_subnet_name must not be empty."
  }
}
variable "public_route_table_name" {
  type        = string
  default     = "mo-rt"
  description = "Name tag for the public route table"

  validation {
    condition     = length(var.public_route_table_name) > 0
    error_message = "public_route_table_name must not be empty."
  }
}
