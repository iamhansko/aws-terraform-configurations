variable "vpc_cidr_block" {
  type        = string
  default     = "10.100.0.0/16"
  description = "CIDR block for the VPC, as the _monolithic template had it"

  validation {
    condition     = can(cidrhost(var.vpc_cidr_block, 0))
    error_message = "vpc_cidr_block must be a valid IPv4 CIDR block (e.g. 10.100.0.0/16)."
  }

  validation {
    # Every subnet is carved out with cidrsubnet(..., 24 - prefix, n), so a prefix longer than /24 makes
    # newbits negative and the plan fails with a message that does not name this variable.
    condition     = tonumber(split("/", var.vpc_cidr_block)[1]) <= 24
    error_message = "vpc_cidr_block must be /24 or shorter, because each subnet is carved out of it as a /24."
  }
}
variable "availability_zone_suffixes" {
  type        = list(string)
  default     = ["a", "b"]
  description = "The two AZ letters the subnet pairs are placed in, appended to the region name. [\"a\", \"b\"] is what the _monolithic template used. Exactly two, because this module declares a named subnet pair per zone rather than generating them"

  validation {
    condition     = length(var.availability_zone_suffixes) == 2
    error_message = "availability_zone_suffixes must contain exactly two entries, because this module declares one public and one private subnet per zone by name rather than by for_each."
  }

  validation {
    condition     = alltrue([for suffix in var.availability_zone_suffixes : can(regex("^[a-z]$", suffix))])
    error_message = "availability_zone_suffixes entries must each be a single lowercase letter (e.g. a), which is appended to the region name to form the zone."
  }

  validation {
    condition     = var.availability_zone_suffixes[0] != var.availability_zone_suffixes[1]
    error_message = "availability_zone_suffixes entries must differ. An internet-facing ALB needs subnets in two different zones, and both NAT gateways would otherwise land in the same one."
  }
}
variable "enable_dns_support" {
  type        = bool
  default     = true
  description = "Whether the VPC resolves names through the Amazon-provided resolver. Required here: the container instances resolve the ECS and ECR endpoints through it, and the workbench resolves github.com"
}
variable "enable_dns_hostnames" {
  type        = bool
  default     = true
  description = "Whether instances launched in the VPC receive public DNS hostnames"
}
variable "vpc_name" {
  type        = string
  default     = "ecs-cicd-vpc"
  description = "Name tag for the VPC"

  validation {
    condition     = length(var.vpc_name) > 0
    error_message = "vpc_name must not be empty."
  }
}
variable "internet_gateway_name" {
  type        = string
  default     = "ecs-cicd-igw"
  description = "Name tag for the internet gateway"

  validation {
    condition     = length(var.internet_gateway_name) > 0
    error_message = "internet_gateway_name must not be empty."
  }
}
variable "nat_gateway_name" {
  type        = string
  default     = "ecs-cicd-natgw"
  description = "Base name tag for the two NAT gateways and their elastic IPs, suffixed with the AZ letter (e.g. ecs-cicd-natgw-a)"

  validation {
    condition     = length(var.nat_gateway_name) > 0
    error_message = "nat_gateway_name must not be empty."
  }
}
variable "public_subnet_name" {
  type        = string
  default     = "ecs-cicd-public"
  description = "Base name tag for the public subnets, suffixed with the AZ letter (e.g. ecs-cicd-public-a)"

  validation {
    condition     = length(var.public_subnet_name) > 0
    error_message = "public_subnet_name must not be empty."
  }
}
variable "private_subnet_name" {
  type        = string
  default     = "ecs-cicd-private"
  description = "Base name tag for the private subnets, suffixed with the AZ letter (e.g. ecs-cicd-private-a)"

  validation {
    condition     = length(var.private_subnet_name) > 0
    error_message = "private_subnet_name must not be empty."
  }
}
variable "public_route_table_name" {
  type        = string
  default     = "ecs-cicd-public-rt"
  description = "Name tag for the shared public route table"

  validation {
    condition     = length(var.public_route_table_name) > 0
    error_message = "public_route_table_name must not be empty."
  }
}
variable "private_route_table_name" {
  type        = string
  default     = "ecs-cicd-private"
  description = "Base name tag for the per-zone private route tables, suffixed with the AZ letter and -rt (e.g. ecs-cicd-private-a-rt)"

  validation {
    condition     = length(var.private_route_table_name) > 0
    error_message = "private_route_table_name must not be empty."
  }
}
