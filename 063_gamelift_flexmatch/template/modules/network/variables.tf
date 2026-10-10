variable "region" {
  type        = string
  description = "Region the VPC is built in. The availability zones are this plus a suffix letter. Passed in rather than read with a data source here, so this module declares none (rules.md D-6)"

  validation {
    condition     = can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]$", var.region))
    error_message = "region must be a region code such as ap-northeast-2."
  }
}
variable "vpc_cidr_block" {
  type        = string
  default     = "10.0.0.0/16"
  description = "CIDR block for the VPC, as the _monolithic template had it"

  validation {
    condition     = can(cidrhost(var.vpc_cidr_block, 0))
    error_message = "vpc_cidr_block must be a valid IPv4 CIDR block (e.g. 10.0.0.0/16)."
  }
}
variable "availability_zone_suffixes" {
  type        = list(string)
  default     = ["a", "b"]
  description = "The two AZ letters the subnet pairs are placed in, appended to the region. The _monolithic template's AzMapping also had a \"c\" entry that nothing used"

  validation {
    condition     = length(var.availability_zone_suffixes) == 2
    error_message = "availability_zone_suffixes must contain exactly two entries, because this module declares one named public and one named private subnet per zone."
  }
  validation {
    condition     = alltrue([for suffix in var.availability_zone_suffixes : can(regex("^[a-z]$", suffix))])
    error_message = "availability_zone_suffixes entries must each be a single lowercase letter (e.g. a)."
  }
  validation {
    condition     = length(distinct(var.availability_zone_suffixes)) == 2
    error_message = "availability_zone_suffixes entries must differ. The ElastiCache subnet group and the VPC-attached Lambda functions are meant to span two zones."
  }
}
variable "public_subnet_cidr_blocks" {
  type        = list(string)
  default     = ["10.0.0.0/24", "10.0.2.0/24"]
  description = "CIDR blocks of the public subnets, in zone order. The defaults are the _monolithic template's AzMapping values for a and b"

  validation {
    condition     = length(var.public_subnet_cidr_blocks) == 2 && alltrue([for cidr in var.public_subnet_cidr_blocks : can(cidrhost(cidr, 0))])
    error_message = "public_subnet_cidr_blocks must contain exactly two valid IPv4 CIDR blocks, one per zone."
  }
}
variable "private_subnet_cidr_blocks" {
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.3.0/24"]
  description = "CIDR blocks of the private subnets, in zone order. The defaults are the _monolithic template's AzMapping values for a and b"

  validation {
    condition     = length(var.private_subnet_cidr_blocks) == 2 && alltrue([for cidr in var.private_subnet_cidr_blocks : can(cidrhost(cidr, 0))])
    error_message = "private_subnet_cidr_blocks must contain exactly two valid IPv4 CIDR blocks, one per zone."
  }
}
variable "enable_dns_support" {
  type        = bool
  default     = true
  description = "Whether the VPC resolves names through the Amazon-provided resolver. The Lambda functions resolve the ElastiCache endpoint through it"
}
variable "enable_dns_hostnames" {
  type        = bool
  default     = true
  description = "Whether instances launched in the VPC receive public DNS hostnames"
}
variable "vpc_name" {
  type        = string
  default     = "vpc"
  description = "Name tag for the VPC"

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
variable "nat_gateway_name" {
  type        = string
  default     = "natgw"
  description = "Base name tag for the two NAT gateways and their elastic IPs, suffixed with the AZ letter (e.g. natgw-a)"

  validation {
    condition     = length(var.nat_gateway_name) > 0
    error_message = "nat_gateway_name must not be empty."
  }
}
variable "public_subnet_name" {
  type        = string
  default     = "public-subnet"
  description = "Base name tag for the public subnets, suffixed with the AZ letter (e.g. public-subnet-a)"

  validation {
    condition     = length(var.public_subnet_name) > 0
    error_message = "public_subnet_name must not be empty."
  }
}
variable "private_subnet_name" {
  type        = string
  default     = "private-subnet"
  description = "Base name tag for the private subnets, suffixed with the AZ letter (e.g. private-subnet-a)"

  validation {
    condition     = length(var.private_subnet_name) > 0
    error_message = "private_subnet_name must not be empty."
  }
}
variable "public_route_table_name" {
  type        = string
  default     = "public-rt"
  description = "Name tag for the shared public route table"

  validation {
    condition     = length(var.public_route_table_name) > 0
    error_message = "public_route_table_name must not be empty."
  }
}
variable "private_route_table_name" {
  type        = string
  default     = "private-rt"
  description = "Base name tag for the per-zone private route tables, suffixed with the AZ letter (e.g. private-rt-a)"

  validation {
    condition     = length(var.private_route_table_name) > 0
    error_message = "private_route_table_name must not be empty."
  }
}
