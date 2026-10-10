variable "vpc_id" {
  type        = string
  description = "VPC ID the group is created in"
  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must be a valid VPC ID (e.g. vpc-0123456789abcdef0)."
  }
}
variable "name" {
  type        = string
  default     = "ecs-service-sg"
  description = "Name of the group, as the _monolithic template named it"
  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.name)) && !startswith(var.name, "sg-")
    error_message = "name must be 1-255 characters from the set AWS accepts for a security group name (a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*, no apostrophe) and must not start with \"sg-\", which EC2 reserves for security group IDs."
  }
}
variable "description" {
  type        = string
  default     = "Security Group"
  description = "Description attached to the group, as the template had it. Changing it replaces the group - and because every task ENI and the database's ingress rule reference it, that replacement reaches further than it looks (rules.md F-1)"
  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.description))
    error_message = "description must be 1-255 characters from the set AWS accepts for a security group description: a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*. An apostrophe is NOT allowed - EC2 rejects CreateSecurityGroup with InvalidParameterValue (rules.md F-1)."
  }
}
variable "port" {
  type        = number
  default     = 8080
  description = "The application port the per-source rules open, as the template had it. The same value is the container port in each task definition and the port the health check and the README's curl commands use - the caller passes one value to all of them (rules.md B-5)"
  validation {
    condition     = var.port > 0 && var.port <= 65535
    error_message = "port must be a valid TCP port."
  }
}
variable "all_traffic_cidr_blocks" {
  type        = list(string)
  default     = []
  description = "CIDR blocks allowed inbound on every protocol and port. The caller passes the VPC CIDR, which is what the template's first ingress block did. Empty leaves only the per-source rules, which is the narrower configuration and is enough for everything in this project"
  validation {
    condition     = alltrue([for cidr in var.all_traffic_cidr_blocks : can(cidrhost(cidr, 0))])
    error_message = "all_traffic_cidr_blocks must contain valid IPv4 CIDR blocks."
  }
}
variable "port_source_security_groups" {
  type        = map(string)
  default     = {}
  description = "Security groups allowed inbound on port, keyed by a caller-chosen label. A map rather than a list because these IDs are other modules' outputs and unknown at plan time, and for_each keys have to be known then (rules.md B-8). The key appears in the rule description, so a plan shows which source it is"
  validation {
    condition     = alltrue([for label in keys(var.port_source_security_groups) : can(regex("^[a-zA-Z0-9._-]+$", label))])
    error_message = "port_source_security_groups keys must be letters, digits, dots, underscores or hyphens, because they end up in a security group rule description (rules.md F-1)."
  }
  validation {
    condition     = alltrue([for id in values(var.port_source_security_groups) : can(regex("^sg-[0-9a-f]+$", id))])
    error_message = "port_source_security_groups values must be valid security group IDs (e.g. sg-0123456789abcdef0)."
  }
}
