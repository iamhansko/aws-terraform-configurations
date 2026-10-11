variable "region" {
  type        = string
  description = "Region the subnets' availability zones are named from. Passed in by the caller rather than read here with data.aws_region, as every module that needs a region string gets it (rules.md I-3)"

  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]$", var.region))
    error_message = "region must look like an AWS region (e.g. ap-northeast-2)."
  }
}
variable "name_prefix" {
  type        = string
  description = "Prefix of the Name tag on every resource in the module, e.g. <prefix>-vpc, <prefix>-public-a, <prefix>-data-plane-b"

  validation {
    # Name tag values may be up to 256 characters; the longest suffix appended is "-data-plane-a".
    condition     = length(var.name_prefix) > 0 && length(var.name_prefix) <= 240
    error_message = "name_prefix must be 1-240 characters, so the longest Name tag built from it stays within the 256 characters EC2 allows for a tag value."
  }
}
variable "vpc_cidr_block" {
  type        = string
  description = "Primary CIDR block of the VPC. The public and the RFC 1918 private subnets are carved from it"

  validation {
    condition     = can(cidrhost(var.vpc_cidr_block, 0))
    error_message = "vpc_cidr_block must be a valid IPv4 CIDR block (e.g. 10.1.0.0/16)."
  }
}
variable "secondary_cidr_block" {
  type        = string
  description = "Secondary CIDR block associated with the VPC, from which the data plane subnets are carved. Separate from the primary because it holds every node and pod address and is sized for that, while the primary only has to hold load balancers, the NAT gateway and the workbench"

  validation {
    condition     = can(cidrhost(var.secondary_cidr_block, 0))
    error_message = "secondary_cidr_block must be a valid IPv4 CIDR block (e.g. 100.64.0.0/16)."
  }
}
variable "public_subnet_cidr_blocks" {
  type        = list(string)
  description = "CIDR blocks of the two public subnets, zone a first. Inside vpc_cidr_block"

  validation {
    condition     = length(var.public_subnet_cidr_blocks) == 2 && alltrue([for c in var.public_subnet_cidr_blocks : can(cidrhost(c, 0))])
    error_message = "public_subnet_cidr_blocks must contain exactly two valid IPv4 CIDR blocks, one per availability zone."
  }
  validation {
    # A subnet outside the VPC's range passes plan and fails CreateSubnet with InvalidSubnet.Range
    # partway through apply. Truncating the subnet's address to the VPC's prefix length and
    # comparing network addresses is the containment check Terraform has no function for. try(),
    # because every validation block is evaluated and a malformed value is the first one's to report.
    condition     = try(alltrue([for c in var.public_subnet_cidr_blocks : cidrhost("${split("/", c)[0]}/${split("/", var.vpc_cidr_block)[1]}", 0) == cidrhost(var.vpc_cidr_block, 0)]), true)
    error_message = "public_subnet_cidr_blocks must all lie inside vpc_cidr_block."
  }
}
variable "private_subnet_cidr_blocks" {
  type        = list(string)
  description = "CIDR blocks of the two RFC 1918 private subnets, zone a first. Inside vpc_cidr_block"

  validation {
    condition     = length(var.private_subnet_cidr_blocks) == 2 && alltrue([for c in var.private_subnet_cidr_blocks : can(cidrhost(c, 0))])
    error_message = "private_subnet_cidr_blocks must contain exactly two valid IPv4 CIDR blocks, one per availability zone."
  }
  validation {
    condition     = try(alltrue([for c in var.private_subnet_cidr_blocks : cidrhost("${split("/", c)[0]}/${split("/", var.vpc_cidr_block)[1]}", 0) == cidrhost(var.vpc_cidr_block, 0)]), true)
    error_message = "private_subnet_cidr_blocks must all lie inside vpc_cidr_block."
  }
}
variable "data_plane_subnet_cidr_blocks" {
  type        = list(string)
  description = "CIDR blocks of the two data plane subnets, zone a first. Inside secondary_cidr_block - these hold the EKS control plane ENIs, every node and every pod"

  validation {
    condition     = length(var.data_plane_subnet_cidr_blocks) == 2 && alltrue([for c in var.data_plane_subnet_cidr_blocks : can(cidrhost(c, 0))])
    error_message = "data_plane_subnet_cidr_blocks must contain exactly two valid IPv4 CIDR blocks, one per availability zone."
  }
  validation {
    condition     = try(alltrue([for c in var.data_plane_subnet_cidr_blocks : cidrhost("${split("/", c)[0]}/${split("/", var.secondary_cidr_block)[1]}", 0) == cidrhost(var.secondary_cidr_block, 0)]), true)
    error_message = "data_plane_subnet_cidr_blocks must all lie inside secondary_cidr_block."
  }
}
variable "public_subnet_tags" {
  type        = map(string)
  default     = {}
  description = "Extra tags on the public subnets, e.g. kubernetes.io/role/elb for the AWS Load Balancer Controller's subnet discovery (rules.md G-1)"
}
variable "private_subnet_tags" {
  type        = map(string)
  default     = {}
  description = "Extra tags on both private tiers - the RFC 1918 subnets and the data plane subnets - e.g. kubernetes.io/role/internal-elb (rules.md G-1)"
}
