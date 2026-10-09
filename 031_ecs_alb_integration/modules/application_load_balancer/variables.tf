variable "name" {
  type        = string
  description = "Name of the load balancer"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{0,30}[a-zA-Z0-9]$", var.name))
    error_message = "name must be 2-32 characters of letters, digits and hyphens, not beginning or ending with a hyphen."
  }
}
variable "vpc_id" {
  type        = string
  description = "VPC the security group and the target group are created in"

  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must be a valid VPC ID (e.g. vpc-0123456789abcdef0)."
  }
}
variable "vpc_cidr_block" {
  type        = string
  description = "CIDR block of the VPC, used as the destination of the load balancer's egress rule so it can reach its targets and nothing else"

  validation {
    condition     = can(cidrhost(var.vpc_cidr_block, 0))
    error_message = "vpc_cidr_block must be a valid IPv4 CIDR block (e.g. 10.10.0.0/16)."
  }
}
variable "subnet_ids" {
  type        = list(string)
  description = "Public subnets the load balancer's nodes are placed in"

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "subnet_ids must contain at least two subnets, because elbv2 rejects an internet-facing application load balancer spanning fewer than two availability zones."
  }

  validation {
    condition     = alltrue([for id in var.subnet_ids : can(regex("^subnet-[0-9a-f]+$", id))])
    error_message = "subnet_ids must contain valid subnet IDs (e.g. subnet-0123456789abcdef0)."
  }
}
variable "security_group_name" {
  type        = string
  default     = "alb-sg"
  description = "Name of the load balancer's security group"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.security_group_name)) && !startswith(var.security_group_name, "sg-")
    error_message = "security_group_name must be 1-255 characters from the set AWS accepts for a security group name (a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*, no apostrophe) and must not start with \"sg-\", which EC2 reserves for security group IDs."
  }
}
variable "security_group_description" {
  type        = string
  default     = "Listener port inbound and the target port outbound for the public ALB"
  description = "Description attached to the load balancer's security group. Changing it replaces the group, because EC2 has no API for modifying a description (rules.md F-1)"

  validation {
    condition     = length(var.security_group_description) > 0
    error_message = "security_group_description must not be empty. Omitting it entirely makes the provider write \"Managed by Terraform\" instead, but an empty string is rejected."
  }

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.security_group_description))
    error_message = "security_group_description must be 1-255 characters from the set AWS accepts for a security group description: a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*. An apostrophe is NOT allowed - EC2 rejects CreateSecurityGroup with InvalidParameterValue, which otherwise only surfaces partway through an apply (rules.md F-1)."
  }
}
variable "ingress_cidr_blocks" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = "Sources allowed to reach the listener port"

  validation {
    condition     = alltrue([for cidr in var.ingress_cidr_blocks : can(cidrhost(cidr, 0))])
    error_message = "ingress_cidr_blocks must contain valid IPv4 CIDR blocks (e.g. 203.0.113.0/24)."
  }
}
variable "listener_port" {
  type        = number
  default     = 80
  description = "Port the load balancer listens on"

  validation {
    condition     = var.listener_port > 0 && var.listener_port <= 65535
    error_message = "listener_port must be a valid TCP port."
  }
}
variable "target_group_name" {
  type        = string
  description = "Name of the target group"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{0,30}[a-zA-Z0-9]$", var.target_group_name))
    error_message = "target_group_name must be 2-32 characters of letters, digits and hyphens, not beginning or ending with a hyphen."
  }
}
variable "target_port" {
  type        = number
  default     = 80
  description = "Port the targets listen on, used by the target group, its health check and the egress rule"

  validation {
    condition     = var.target_port > 0 && var.target_port <= 65535
    error_message = "target_port must be a valid TCP port."
  }
}
variable "health_check_path" {
  type        = string
  default     = "/"
  description = "Path the health check requests on each target"

  validation {
    condition     = startswith(var.health_check_path, "/")
    error_message = "health_check_path must start with '/'."
  }
}
