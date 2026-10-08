variable "vpc_cidr_block" {
  type        = string
  default     = "10.0.0.0/16"
  description = "CIDR block for the VPC, as the _monolithic template had it"

  validation {
    condition     = can(cidrhost(var.vpc_cidr_block, 0))
    error_message = "vpc_cidr_block must be a valid IPv4 CIDR block (e.g. 10.0.0.0/16)."
  }

  validation {
    # Every subnet is carved out with cidrsubnet(..., 24 - prefix, n), so a prefix longer than /24 makes
    # newbits negative and the plan fails with a message about extending the prefix by a negative number -
    # which does not name this variable, so it reads as a bug in main.tf rather than a bad input here.
    condition     = tonumber(split("/", var.vpc_cidr_block)[1]) <= 24
    error_message = "vpc_cidr_block must be /24 or shorter, because each subnet is carved out of it as a /24."
  }
}
variable "enable_dns_support" {
  type        = bool
  default     = true
  description = "Whether the VPC provides DNS resolution through the Amazon-provided resolver. True is required here, and not only for convenience: the ECS agent on every container instance resolves ecs.<region>.amazonaws.com to register, and the image builder resolves the ECR registry to push to it"
}
variable "enable_dns_hostnames" {
  type        = bool
  default     = true
  description = "Whether instances launched in the VPC receive public DNS hostnames"
}
variable "vpc_name" {
  type        = string
  default     = "ecs-volumes-vpc"
  description = "Name tag for the VPC"

  validation {
    condition     = length(var.vpc_name) > 0
    error_message = "vpc_name must not be empty."
  }
}
variable "internet_gateway_name" {
  type        = string
  default     = "ecs-volumes-igw"
  description = "Name tag for the internet gateway"

  validation {
    condition     = length(var.internet_gateway_name) > 0
    error_message = "internet_gateway_name must not be empty."
  }
}
variable "nat_gateway_name" {
  type        = string
  default     = "ecs-volumes-natgw"
  description = "Name tag for the NAT gateway"

  validation {
    condition     = length(var.nat_gateway_name) > 0
    error_message = "nat_gateway_name must not be empty."
  }
}
variable "public_subnet_name" {
  type        = string
  default     = "ecs-volumes-public"
  description = "Base name tag for the public subnets, suffixed with the AZ letter (e.g. ecs-volumes-public-a)"

  validation {
    condition     = length(var.public_subnet_name) > 0
    error_message = "public_subnet_name must not be empty."
  }
}
variable "private_subnet_name" {
  type        = string
  default     = "ecs-volumes-private"
  description = "Base name tag for the private subnets, suffixed with the AZ letter (e.g. ecs-volumes-private-a)"

  validation {
    condition     = length(var.private_subnet_name) > 0
    error_message = "private_subnet_name must not be empty."
  }
}
variable "public_route_table_name" {
  type        = string
  default     = "ecs-volumes-public-rt"
  description = "Name tag for the public route table"

  validation {
    condition     = length(var.public_route_table_name) > 0
    error_message = "public_route_table_name must not be empty."
  }
}
variable "private_route_table_name" {
  type        = string
  default     = "ecs-volumes-private-rt"
  description = "Name tag for the private route table"

  validation {
    condition     = length(var.private_route_table_name) > 0
    error_message = "private_route_table_name must not be empty."
  }
}
variable "availability_zone_suffixes" {
  type        = list(string)
  default     = ["a", "c"]
  description = <<-DESC
    The two AZ letters the subnets are placed in, appended to the region name. ["a", "c"] is what the
    _monolithic template's resources used.

    Exactly two, because the module declares a named subnet pair per zone rather than generating them -
    see main.tf for why the count is two and why this is not a free-length list.

    The letters are worth checking against the instance type the container instances use. An Auto Scaling
    group spanning a zone that has no capacity for that family does not fail in Terraform: apply returns
    successfully and the shortfall appears only as a failed scaling activity, so the cluster sits with
    fewer container instances than desired_capacity and tasks stay PENDING.
  DESC

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
    error_message = "availability_zone_suffixes entries must differ. Two subnets in one zone would satisfy the ECS service's spread placement strategy without spreading anything, and the regional NAT gateway would be given two addresses in the same zone."
  }
}
variable "public_subnet_tags" {
  type        = map(string)
  default     = {}
  description = "Tags merged into both public subnets on top of their Name tag. Empty by default: the kubernetes.io/role/elb tag the EKS projects in this repository default to exists so the AWS Load Balancer Controller can auto-discover subnets, and there is no cluster or load balancer here"

  validation {
    condition     = alltrue([for key in keys(var.public_subnet_tags) : length(key) > 0])
    error_message = "public_subnet_tags must not contain empty tag keys."
  }
}
variable "private_subnet_tags" {
  type        = map(string)
  default     = {}
  description = "Tags merged into both private subnets on top of their Name tag"

  validation {
    condition     = alltrue([for key in keys(var.private_subnet_tags) : length(key) > 0])
    error_message = "private_subnet_tags must not contain empty tag keys."
  }
}
