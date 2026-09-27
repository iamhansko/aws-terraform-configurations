variable "vpc_id" {
  type        = string
  description = "VPC the endpoints are created in"

  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must be a valid VPC ID (e.g. vpc-0123456789abcdef0)."
  }
}
variable "subnet_ids" {
  type        = list(string)
  description = "Subnets the interface endpoints place their ENIs in. The private subnets: an interface endpoint is reachable from wherever its ENI lives, so putting them here is what gives the egress-less private subnets a path to these AWS APIs"

  validation {
    condition     = length(var.subnet_ids) > 0 && alltrue([for s in var.subnet_ids : can(regex("^subnet-[0-9a-f]+$", s))])
    error_message = "subnet_ids must contain at least one valid subnet ID."
  }
}
variable "route_table_ids" {
  type        = list(string)
  description = "Route tables the S3 gateway endpoint attaches to. A gateway endpoint is not an ENI - it works by adding the service's prefix list as a route - so it takes route tables where the interface endpoints take subnets"

  validation {
    condition     = length(var.route_table_ids) > 0
    error_message = "route_table_ids must contain at least one route table ID, or the S3 gateway endpoint has nowhere to add its route."
  }
}
variable "security_group_ids" {
  type        = list(string)
  description = "Security groups on the interface endpoint ENIs. This project passes the EKS cluster security group: pods on this cluster carry that group, and it allows traffic from itself, so pods can reach the endpoints without a separate rule. The consequence is that the endpoints cannot be created until the cluster exists (rules.md B-6)"

  validation {
    condition     = length(var.security_group_ids) > 0 && alltrue([for s in var.security_group_ids : can(regex("^sg-[0-9a-f]+$", s))])
    error_message = "security_group_ids must contain at least one valid security group ID. An interface endpoint with no security group falls back to the VPC default group, which usually denies the traffic that was supposed to reach it."
  }
}
variable "interface_services" {
  type        = set(string)
  description = "Short service names for the interface endpoints, expanded to com.amazonaws.<region>.<name>. Each one is here because something in the cluster would otherwise have no way to reach it: ecr.api and ecr.dkr for pulling images, sts for IRSA token exchange, ec2 for the VPC CNI's ENI calls, eks for the kubelet's cluster lookups, ssm and ssmmessages for Systems Manager, elasticloadbalancing for the load balancer controller"
  default = [
    "ecr.api",
    "ecr.dkr",
    "ec2",
    "sts",
    "eks",
    "ssm",
    "ssmmessages",
    "elasticloadbalancing",
  ]

  validation {
    condition     = length(var.interface_services) > 0
    error_message = "interface_services must not be empty. With no NAT gateway and no interface endpoints, nothing in the private subnets can reach any AWS API at all."
  }
  validation {
    condition     = alltrue([for s in var.interface_services : can(regex("^[a-z0-9.-]+$", s))])
    error_message = "interface_services entries are short service names such as ecr.api or sts, not full com.amazonaws.<region>.<name> strings."
  }
}
variable "create_s3_gateway_endpoint" {
  type        = bool
  default     = true
  description = "Whether to create the S3 gateway endpoint. Needed because ECR stores image layers in S3: an ecr.dkr endpoint on its own gets the manifest and then the layer pull fails, which looks like an image pull timeout rather than a missing endpoint"
}
variable "private_dns_enabled" {
  type        = bool
  default     = true
  description = "Whether each interface endpoint takes over the service's public DNS name inside the VPC. True is what makes this transparent: without it, clients keep resolving the public name, get a public address, and fail - so every caller would have to be reconfigured with the endpoint-specific hostname"
}
variable "name_prefix" {
  type        = string
  default     = "private-cluster"
  description = "Prefix for the Name tag on each endpoint"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.name_prefix))
    error_message = "name_prefix must be letters, digits and hyphens."
  }
}
