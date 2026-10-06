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
variable "additional_security_group_ids" {
  type        = list(string)
  default     = []
  description = "Extra security groups attached to the interface endpoint ENIs alongside the one this module creates. Empty here: the point of this project is that the cluster reaches the endpoints through one explicit rule, not because it happens to share a group with them (rules.md B-6)"

  validation {
    condition     = alltrue([for s in var.additional_security_group_ids : can(regex("^sg-[0-9a-f]+$", s))])
    error_message = "additional_security_group_ids must contain valid security group IDs (e.g. sg-0123456789abcdef0)."
  }
}
variable "security_group_name" {
  type        = string
  default     = "vpce-sg"
  description = "Name of the security group in front of the interface endpoints, as the _monolithic template named it"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.security_group_name)) && !startswith(var.security_group_name, "sg-")
    error_message = "security_group_name must be 1-255 characters from the set AWS accepts for a security group name (a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*, no apostrophe) and must not start with \"sg-\"."
  }
}
variable "security_group_description" {
  type        = string
  default     = "Inbound HTTPS to the interface VPC endpoints from the EKS cluster security group"
  description = "Description attached to the endpoint security group. Changing it replaces the group, and every endpoint referencing it with it, so it is worth getting right the first time (rules.md F-1)"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.security_group_description))
    error_message = "security_group_description must be 1-255 characters from the set AWS accepts for a security group description: a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*. An apostrophe is NOT allowed - EC2 rejects CreateSecurityGroup with InvalidParameterValue, which otherwise only surfaces at apply time (rules.md F-1)."
  }
}
variable "endpoint_port" {
  type        = number
  default     = 443
  description = "Port the interface endpoints answer on. Every AWS API endpoint is HTTPS, so this is 443 and there is no second port to open"

  validation {
    condition     = var.endpoint_port > 0 && var.endpoint_port <= 65535
    error_message = "endpoint_port must be a valid TCP port."
  }
}
variable "ingress_source_security_groups" {
  type        = map(string)
  default     = {}
  description = "Security groups allowed inbound on endpoint_port, keyed by a caller-chosen label that appears in the rule descriptions and resource addresses. A map rather than a list because these IDs are usually another module's output, unknown until apply, and for_each needs statically known keys (rules.md B-8)"

  validation {
    condition     = alltrue([for label in keys(var.ingress_source_security_groups) : can(regex("^[a-zA-Z0-9._-]+$", label))])
    error_message = "ingress_source_security_groups keys become part of a rule description, so each must be letters, digits, dots, underscores or hyphens - an apostrophe is rejected by EC2 at apply time (rules.md F-1)."
  }
  validation {
    condition     = alltrue([for id in values(var.ingress_source_security_groups) : can(regex("^sg-[0-9a-f]+$", id))])
    error_message = "ingress_source_security_groups must contain valid security group IDs (e.g. sg-0123456789abcdef0)."
  }
}
variable "ingress_cidr_blocks" {
  type        = list(string)
  default     = []
  description = "CIDRs allowed inbound on endpoint_port. Empty here - the cluster security group is named as a source instead, which is what keeps the rule readable when the VPC CIDR changes"

  validation {
    condition     = alltrue([for c in var.ingress_cidr_blocks : can(cidrhost(c, 0))])
    error_message = "ingress_cidr_blocks must contain valid IPv4 CIDR blocks."
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
