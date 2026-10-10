variable "vpc_cidr_block" {
  type        = string
  default     = "10.0.0.0/16"
  description = "CIDR block for the VPC, as the _monolithic template's VpcMapping had it"
  validation {
    condition     = can(cidrhost(var.vpc_cidr_block, 0))
    error_message = "vpc_cidr_block must be a valid IPv4 CIDR block (e.g. 10.0.0.0/16)."
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
  description = "The two AZ letters the subnet pairs are placed in, appended to the region name. [\"a\", \"b\"] is what the _monolithic template's resources used; its AzMapping also defined \"c\", which nothing referenced. Exactly two, because this module declares a named subnet pair per zone rather than generating them"
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
    error_message = "availability_zone_suffixes entries must differ. An RDS DB subnet group is rejected unless its subnets span two Availability Zones, and multi_az on the primary instance has nowhere to put the standby."
  }
}
variable "enable_dns_support" {
  type        = bool
  default     = true
  description = "Whether the VPC provides DNS resolution through the Amazon-provided resolver. Required here: an awsvpc task resolves the DynamoDB, Secrets Manager and CloudWatch Logs endpoints through it, and the RDS instance endpoint is a DNS name"
}
variable "enable_dns_hostnames" {
  type        = bool
  default     = true
  description = "Whether instances launched in the VPC receive public DNS hostnames. Also what makes ECS give an awsvpc task an internal DNS hostname rather than a random one"
}
variable "map_public_ip_on_launch" {
  type        = bool
  default     = true
  description = "Whether instances launched into the public subnets get a public IPv4 address automatically, as the _monolithic template had it. The workbench instance also asks for one explicitly, so this is belt and braces for anything launched there by hand"
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
variable "nat_gateway_name_prefix" {
  type        = string
  default     = "natgw-"
  description = "Prefix for the NAT gateway and elastic IP name tags, suffixed with the AZ letter (e.g. natgw-a)"
  validation {
    condition     = length(var.nat_gateway_name_prefix) > 0
    error_message = "nat_gateway_name_prefix must not be empty."
  }
}
variable "public_subnet_name_prefix" {
  type        = string
  default     = "public-subnet-"
  description = "Prefix for the public subnet name tags, suffixed with the AZ letter (e.g. public-subnet-a)"
  validation {
    condition     = length(var.public_subnet_name_prefix) > 0
    error_message = "public_subnet_name_prefix must not be empty."
  }
}
variable "private_subnet_name_prefix" {
  type        = string
  default     = "private-subnet-"
  description = "Prefix for the private subnet name tags, suffixed with the AZ letter (e.g. private-subnet-a)"
  validation {
    condition     = length(var.private_subnet_name_prefix) > 0
    error_message = "private_subnet_name_prefix must not be empty."
  }
}
variable "public_route_table_name" {
  type        = string
  default     = "public-rt"
  description = "Name tag for the single public route table both public subnets are associated with"
  validation {
    condition     = length(var.public_route_table_name) > 0
    error_message = "public_route_table_name must not be empty."
  }
}
variable "private_route_table_name_prefix" {
  type        = string
  default     = "private-rt-"
  description = "Prefix for the per-zone private route table name tags, suffixed with the AZ letter (e.g. private-rt-a). One table per zone, because each points at that zone's own NAT gateway"
  validation {
    condition     = length(var.private_route_table_name_prefix) > 0
    error_message = "private_route_table_name_prefix must not be empty."
  }
}
variable "public_subnet_tags" {
  type        = map(string)
  default     = {}
  description = <<-DESC
    Tags merged into both public subnets on top of their Name tag.

    Empty, where the _monolithic template tagged both public subnets with "kubernetes.io/role/elb" = 1.
    That tag is how the AWS Load Balancer Controller discovers which subnets an internet-facing load
    balancer may span (rules.md G-1), and there is no EKS cluster, no controller and no Kubernetes anything
    in this project - it is a leftover from whichever template this one was copied from. Dropping it is
    deliberate rather than an oversight: a tag that claims a subnet for a controller that does not exist is
    a thing the next reader has to investigate, and an untagged subnet costs nothing because the load
    balancers here are created by Terraform with their subnets named explicitly. The hook stays open so a
    caller that does add a controller can pass it back in.
  DESC
  validation {
    condition     = alltrue([for key in keys(var.public_subnet_tags) : length(key) > 0])
    error_message = "public_subnet_tags must not contain empty tag keys."
  }
}
variable "private_subnet_tags" {
  type        = map(string)
  default     = {}
  description = "Tags merged into both private subnets on top of their Name tag. Empty for the same reason as public_subnet_tags: nothing in this project discovers a subnet by tag"
  validation {
    condition     = alltrue([for key in keys(var.private_subnet_tags) : length(key) > 0])
    error_message = "private_subnet_tags must not contain empty tag keys."
  }
}
