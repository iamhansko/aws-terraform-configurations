variable "name" {
  type        = string
  default     = "public-alb"
  description = "Name of the ALB, as the _monolithic template had it. A literal, so a second copy of this project in the same account fails with DuplicateLoadBalancerName"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{0,30}[a-zA-Z0-9]$", var.name)) && !startswith(var.name, "internal-")
    error_message = "name must be 2-32 characters of letters, digits and hyphens, must not begin or end with a hyphen, and must not begin with internal-."
  }
}
variable "vpc_id" {
  type        = string
  description = "VPC the target groups and the security group are created in"

  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must be a valid VPC ID (e.g. vpc-0123456789abcdef0)."
  }
}
variable "vpc_cidr_block" {
  type        = string
  description = "CIDR block of the VPC. The ALB's only egress rule is to the target port inside it"

  validation {
    condition     = can(cidrhost(var.vpc_cidr_block, 0))
    error_message = "vpc_cidr_block must be a valid IPv4 CIDR block."
  }
}
variable "subnet_ids" {
  type        = list(string)
  description = "Public subnets the ALB is placed in. At least two, in different zones - ELB's own requirement"

  validation {
    condition     = length(var.subnet_ids) >= 2 && alltrue([for id in var.subnet_ids : can(regex("^subnet-[0-9a-f]+$", id))])
    error_message = "subnet_ids must contain at least two valid subnet IDs."
  }
}
variable "security_group_name" {
  type        = string
  default     = "alb-sg"
  description = "Name of the ALB's security group. The _monolithic template only tagged it alb-sg and let EC2 generate the name; naming it the same as the tag makes it findable"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.security_group_name)) && !startswith(var.security_group_name, "sg-")
    error_message = "security_group_name must be 1-255 characters from the set AWS accepts for a security group name (no apostrophe) and must not start with \"sg-\" (rules.md F-1)."
  }
}
variable "allow_inbound_from_anywhere" {
  type        = bool
  default     = true
  description = "Whether the listener port accepts traffic from 0.0.0.0/0. False leaves the ALB with no ingress at all, which is what the _monolithic template's InboundFromAnywhere=False meant"
}
variable "listener_port" {
  type        = number
  default     = 80
  description = "Port the HTTP listener accepts on, as the _monolithic template had it"

  validation {
    condition     = var.listener_port > 0 && var.listener_port <= 65535
    error_message = "listener_port must be a valid TCP port."
  }
}
variable "target_port" {
  type        = number
  description = "Port the targets listen on. Passed from the root's one container port, so the target groups, the health check, the ALB's egress rule and the task definition all agree (rules.md B-5)"

  validation {
    condition     = var.target_port > 0 && var.target_port <= 65535
    error_message = "target_port must be a valid TCP port."
  }
}
variable "health_check_path" {
  type        = string
  default     = "/"
  description = "Path the target groups health check, as the _monolithic template had it"

  validation {
    condition     = startswith(var.health_check_path, "/")
    error_message = "health_check_path must start with /."
  }
}
variable "target_group_names" {
  type = object({
    primary   = string
    alternate = string
  })
  default = {
    primary   = "alb-tg-1"
    alternate = "alb-tg-2"
  }
  description = "Names of the two target groups, as the _monolithic template had them. primary is the group the listener and the production rule forward to and the service registers its tasks into; alternate is the group the service's advanced_configuration names for a blue/green deployment"

  validation {
    condition     = alltrue([for name in values(var.target_group_names) : can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{0,30}[a-zA-Z0-9]$", name))])
    error_message = "target_group_names values must each be 2-32 characters of letters, digits and hyphens, not beginning or ending with a hyphen."
  }
  validation {
    condition     = var.target_group_names.primary != var.target_group_names.alternate
    error_message = "target_group_names.primary and target_group_names.alternate must differ - a target group name is unique per account and region."
  }
}
variable "production_rule_priority" {
  type        = number
  default     = 1
  description = "Priority of the production listener rule, as the _monolithic template had it"

  validation {
    condition     = var.production_rule_priority >= 1 && var.production_rule_priority <= 50000
    error_message = "production_rule_priority must be between 1 and 50000."
  }
}
variable "production_rule_path_patterns" {
  type        = list(string)
  default     = ["/"]
  description = "Path patterns the production rule matches. [\"/\"] matches the root path only, as the _monolithic template had it - every other path falls through to the listener's default action, which forwards to the same group"

  validation {
    condition     = length(var.production_rule_path_patterns) > 0 && length(var.production_rule_path_patterns) <= 5
    error_message = "production_rule_path_patterns must contain between one and five patterns."
  }
}
