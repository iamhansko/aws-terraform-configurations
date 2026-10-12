variable "region" {
  type        = string
  description = "Region the endpoint service names are built from (com.amazonaws.<region>.<service>). Passed in rather than read with data.aws_region, because this module is called with depends_on and a data source inside it would be deferred to apply (rules.md D-6)"

  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]$", var.region))
    error_message = "region must look like an AWS region (e.g. ap-northeast-2)."
  }
}
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
  description = "Subnets the interface endpoints place their ENIs in - the private subnets, where the nodes, the pods and MWAA's workers are. One ENI per subnet per service, and each is billed by the hour"

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
  description = "Extra security groups attached to the interface endpoint ENIs alongside the one this module creates. The module never looks these up itself (rules.md B-6)"

  validation {
    condition     = alltrue([for s in var.additional_security_group_ids : can(regex("^sg-[0-9a-f]+$", s))])
    error_message = "additional_security_group_ids must contain valid security group IDs (e.g. sg-0123456789abcdef0)."
  }
}
variable "security_group_name" {
  type        = string
  default     = "vpc-endpoints"
  description = "Name of the security group in front of the interface endpoints"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.security_group_name)) && !startswith(var.security_group_name, "sg-")
    error_message = "security_group_name must be 1-255 characters from the set AWS accepts for a security group name (a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*, no apostrophe) and must not start with \"sg-\"."
  }
}
variable "security_group_description" {
  type        = string
  default     = "Security group for VPC endpoint access"
  description = "Description attached to the endpoint security group, as the blueprint worded it. Changing it replaces the group, and every endpoint referencing it with it, so it is worth getting right the first time (rules.md F-1)"

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
  description = "CIDRs allowed inbound on endpoint_port. Pass values known at plan time - a root variable rather than another module's output - because they are for_each keys (rules.md B-8)"

  validation {
    condition     = alltrue([for c in var.ingress_cidr_blocks : can(cidrhost(c, 0))])
    error_message = "ingress_cidr_blocks must contain valid IPv4 CIDR blocks."
  }
}
variable "interface_services" {
  type        = set(string)
  default     = []
  description = "Short service names for the interface endpoints, expanded to com.amazonaws.<region>.<name>. Empty creates none, which the network tolerates because its private subnets route through a NAT gateway"

  validation {
    condition     = alltrue([for s in var.interface_services : can(regex("^[a-z0-9.-]+$", s))])
    error_message = "interface_services entries are short service names such as ecr.api or sts, not full com.amazonaws.<region>.<name> strings."
  }
}
variable "create_s3_gateway_endpoint" {
  type        = bool
  default     = true
  description = "Whether to create the S3 gateway endpoint. Gateway endpoints are free, unlike interface ones, and ECR stores image layers in S3 - so an ecr.dkr interface endpoint without this still sends the bulk of every image pull through the NAT gateway"
}
variable "private_dns_enabled" {
  type        = bool
  default     = true
  description = "Whether each interface endpoint takes over the service's public DNS name inside the VPC. True is what makes the endpoints transparent: without it, clients keep resolving the public name and go out through the NAT gateway as if the endpoint were not there"
}
variable "name_prefix" {
  type        = string
  default     = "vpc-endpoint"
  description = "Prefix for the Name tag on each endpoint, which gets -<service> after it"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.name_prefix))
    error_message = "name_prefix must be letters, digits and hyphens."
  }
}
