variable "name" {
  type        = string
  description = "Name of the ECS service security group"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.name)) && !startswith(var.name, "sg-")
    error_message = "name must be 1-255 characters from the set AWS accepts for a security group name (a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*, no apostrophe) and must not start with \"sg-\", which EC2 reserves for security group IDs."
  }
}
variable "description" {
  type        = string
  description = "Description of the ECS service security group"

  validation {
    condition     = length(var.description) > 0
    error_message = "description must not be empty."
  }
  validation {
    # rules.md F-1. Changing this replaces the group, and both stacks' services reference it - an
    # ECS service cannot have its network configuration changed in place for a CODE_DEPLOY
    # controller, so the replacement reaches further than it looks.
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.description))
    error_message = "description must be 1-255 characters from the set AWS accepts for a security group description: a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*. An apostrophe is NOT allowed - EC2 rejects the CreateSecurityGroup call with InvalidParameterValue, which otherwise only surfaces at apply time."
  }
}
variable "vpc_id" {
  type        = string
  description = "VPC the group is created in. The app VPC, because the tasks run in its private subnets"

  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must be a valid VPC ID (e.g. vpc-0123456789abcdef0)."
  }
}
variable "container_port" {
  type        = number
  description = "Port the application containers listen on, opened to each source group. Both stacks use the same port, which is one of the things they do not differ by - see modules/app_stack"

  validation {
    condition     = var.container_port > 0 && var.container_port <= 65535
    error_message = "container_port must be a valid TCP port."
  }
}
variable "ingress_source_security_groups" {
  type        = map(string)
  default     = {}
  description = "Security groups allowed inbound on container_port, keyed by a caller-chosen label. The application load balancer group and the workbench group here. A map rather than a list because these IDs are another module's output and unknown until apply, and for_each needs statically known keys (rules.md B-8)"

  validation {
    condition     = alltrue([for label in keys(var.ingress_source_security_groups) : can(regex("^[a-zA-Z0-9._-]+$", label))])
    error_message = "ingress_source_security_groups keys land in the rule descriptions, so each must be a non-empty string of letters, digits, dots, underscores or hyphens (rules.md F-1)."
  }
  validation {
    condition     = alltrue([for id in values(var.ingress_source_security_groups) : can(regex("^sg-[0-9a-f]+$", id))])
    error_message = "ingress_source_security_groups must contain valid security group IDs (e.g. sg-0123456789abcdef0)."
  }
}
variable "all_traffic_source_security_groups" {
  type        = map(string)
  default     = {}
  description = "Security groups allowed inbound on every protocol and port, keyed by a caller-chosen label. The root passes the app VPC default security group here, reproducing the _monolithic template"

  validation {
    condition     = alltrue([for label in keys(var.all_traffic_source_security_groups) : can(regex("^[a-zA-Z0-9._-]+$", label))])
    error_message = "all_traffic_source_security_groups keys land in the rule descriptions, so each must be a non-empty string of letters, digits, dots, underscores or hyphens."
  }
  validation {
    condition     = alltrue([for id in values(var.all_traffic_source_security_groups) : can(regex("^sg-[0-9a-f]+$", id))])
    error_message = "all_traffic_source_security_groups must contain valid security group IDs (e.g. sg-0123456789abcdef0)."
  }
}
