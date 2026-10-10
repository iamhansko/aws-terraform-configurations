variable "vpc_id" {
  type        = string
  description = "VPC ID where the security group is created"

  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must be a valid VPC ID (e.g. vpc-0123456789abcdef0)."
  }
}
variable "name" {
  type        = string
  default     = "GomokuDefault"
  description = "Name of the security group, as the _monolithic template named it. Changing it replaces the group (rules.md F-1)"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]+$", var.name)) && length(var.name) <= 255 && !startswith(var.name, "sg-")
    error_message = "name must be 1-255 characters from the set AWS accepts for a security group name (a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*, no apostrophe) and must not start with \"sg-\" (rules.md F-1)."
  }
}
variable "description" {
  type        = string
  default     = "Security Group for Gomoku Resources"
  description = "Description of the security group, as the _monolithic template had it. Changing it replaces the group (rules.md F-1)"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]+$", var.description)) && length(var.description) <= 255
    error_message = "description must be 1-255 characters from the set AWS accepts for a security group description: a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*. An apostrophe is NOT allowed (rules.md F-1)."
  }
}
variable "ingress_source_security_groups" {
  type        = map(string)
  default     = {}
  description = "Security group IDs admitted on ingress_source_port in addition to the group itself, keyed by a caller-chosen label. A map rather than a list because the IDs are other modules' outputs, unknown until apply, and for_each needs keys known at plan (rules.md B-8)"

  validation {
    condition     = alltrue([for label in keys(var.ingress_source_security_groups) : can(regex("^[a-zA-Z0-9._-]+$", label))])
    error_message = "ingress_source_security_groups keys are labels used in rule descriptions and resource addresses, so each must be a non-empty string of letters, digits, dots, underscores or hyphens."
  }
  validation {
    condition     = alltrue([for id in values(var.ingress_source_security_groups) : can(regex("^sg-[0-9a-f]+$", id))])
    error_message = "ingress_source_security_groups must contain valid security group IDs (e.g. sg-0123456789abcdef0)."
  }
}
variable "ingress_source_port" {
  type        = number
  default     = 6379
  description = "TCP port the extra sources in ingress_source_security_groups are admitted on - the Redis port, since that is the only thing in this group anyone outside it needs"

  validation {
    condition     = var.ingress_source_port > 0 && var.ingress_source_port <= 65535
    error_message = "ingress_source_port must be a valid TCP port."
  }
}
