variable "vpc_cidr_block" {
  type        = string
  default     = "10.0.0.0/16"
  description = "CIDR block for the VPC"

  validation {
    condition     = can(cidrhost(var.vpc_cidr_block, 0))
    error_message = "vpc_cidr_block must be a valid IPv4 CIDR block (e.g. 10.0.0.0/16)."
  }
}
variable "enable_dns_support" {
  type        = bool
  default     = true
  description = "Whether the VPC provides DNS resolution through the Amazon-provided resolver"
}
variable "enable_dns_hostnames" {
  type        = bool
  default     = true
  description = "Whether instances launched in the VPC receive public DNS hostnames"
}
variable "vpc_name" {
  type        = string
  default     = "stem-vpc"
  description = "Name tag for the VPC"

  validation {
    condition     = length(var.vpc_name) > 0
    error_message = "vpc_name must not be empty."
  }
}
variable "internet_gateway_name" {
  type        = string
  default     = "stem-igw"
  description = "Name tag for the Internet Gateway"

  validation {
    condition     = length(var.internet_gateway_name) > 0
    error_message = "internet_gateway_name must not be empty."
  }
}
variable "public_subnet_name" {
  type        = string
  default     = "stem-public"
  description = "Base name tag for public subnets, suffixed with the AZ letter (e.g. stem-public-a)"

  validation {
    condition     = length(var.public_subnet_name) > 0
    error_message = "public_subnet_name must not be empty."
  }
}
variable "private_subnet_name" {
  type        = string
  default     = "stem-private"
  description = "Base name tag for private subnets, suffixed with the AZ letter (e.g. stem-private-a)"

  validation {
    condition     = length(var.private_subnet_name) > 0
    error_message = "private_subnet_name must not be empty."
  }
}
variable "public_route_table_name" {
  type        = string
  default     = "stem-public-rt"
  description = "Name tag for the shared public route table"

  validation {
    condition     = length(var.public_route_table_name) > 0
    error_message = "public_route_table_name must not be empty."
  }
}
variable "private_route_table_name" {
  type        = string
  default     = "stem-private-rt"
  description = "Base name tag for the per-AZ private route tables, suffixed with the AZ letter"

  validation {
    condition     = length(var.private_route_table_name) > 0
    error_message = "private_route_table_name must not be empty."
  }
}
variable "nat_gateway_name" {
  type        = string
  default     = "stem-natgw"
  description = "Base name tag for the per-AZ NAT Gateways, suffixed with the AZ letter"

  validation {
    condition     = length(var.nat_gateway_name) > 0
    error_message = "nat_gateway_name must not be empty."
  }
}
variable "public_subnet_tags" {
  type        = map(string)
  default     = {}
  description = "Tags merged into every public subnet, on top of its Name tag. Empty by default, unlike the EKS projects in this repository: the kubernetes.io/role/elb tag they default to exists only so the AWS Load Balancer Controller can auto-discover subnets, and there is no cluster here to discover them"

  validation {
    condition     = alltrue([for key in keys(var.public_subnet_tags) : length(key) > 0])
    error_message = "public_subnet_tags must not contain empty tag keys."
  }
}
variable "private_subnet_tags" {
  type        = map(string)
  default     = {}
  description = "Tags merged into every private subnet, on top of its Name tag. Empty by default for the same reason as public_subnet_tags"

  validation {
    condition     = alltrue([for key in keys(var.private_subnet_tags) : length(key) > 0])
    error_message = "private_subnet_tags must not contain empty tag keys."
  }
}
variable "secondary_cidr_block" {
  type        = string
  default     = null
  description = "A second CIDR associated with the VPC, carrying the pod subnets. Null creates no pod subnets at all, which is what every other project in this repository wants. 100.64.0.0/16 here: CGNAT space, chosen because pod addresses taken from it do not have to be unique across peered or on-premises networks the way the primary RFC 1918 range does"

  validation {
    condition     = var.secondary_cidr_block == null || can(cidrhost(var.secondary_cidr_block, 0))
    error_message = "secondary_cidr_block must be a valid IPv4 CIDR block, or null."
  }
  validation {
    condition     = var.secondary_cidr_block == null || tonumber(split("/", var.secondary_cidr_block)[1]) <= 24
    error_message = "secondary_cidr_block must be /24 or larger, because it is carved into one /24 pod subnet per availability zone."
  }
}
variable "enable_pod_subnet_nat_route" {
  type        = bool
  default     = true
  description = "Whether the pod subnets get a default route through their zone's NAT gateway. True, which departs from the _monolithic template: it created the pod route tables and left them without any route, so a pod calling anything outside the VPC timed out with nothing indicating routing as the cause. Inbound-only workloads do not notice, because the kubelet pulls images over the node's primary interface in a private subnet. Set false to reproduce the original"
}
variable "pod_subnet_name" {
  type        = string
  default     = "pod-subnet"
  description = "Name tag prefix for the pod subnets; the zone letter is appended"

  validation {
    condition     = length(var.pod_subnet_name) > 0
    error_message = "pod_subnet_name must not be empty."
  }
}
variable "pod_route_table_name" {
  type        = string
  default     = "pod-subnet-rt"
  description = "Name tag prefix for the pod subnet route tables; the zone letter is appended"

  validation {
    condition     = length(var.pod_route_table_name) > 0
    error_message = "pod_route_table_name must not be empty."
  }
}
variable "pod_subnet_tags" {
  type        = map(string)
  default     = {}
  description = "Tags merged into every pod subnet. Empty by default and deliberately without the kubernetes.io/role/* load balancer tags: pods live here, but load balancers must not be placed here - a scheme that auto-discovered these subnets would put an ELB in CGNAT space"

  validation {
    condition = alltrue([
      for key, value in var.pod_subnet_tags :
      length(key) > 0 && length(key) <= 128 && length(value) <= 256 && !startswith(lower(key), "aws:")
    ])
    error_message = "pod_subnet_tags keys must be 1-128 characters and must not use the reserved \"aws:\" prefix, and values must be 256 characters or fewer. A misspelled key is not rejected by AWS, so the failure surfaces much later as a controller that cannot auto-discover subnets (rules.md G-1)."
  }
}
