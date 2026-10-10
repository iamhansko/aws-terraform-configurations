variable "vpc_id" {
  type        = string
  description = "VPC the group is created in"

  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must be a valid VPC ID (e.g. vpc-0123456789abcdef0)."
  }
}
variable "name" {
  type        = string
  default     = "GomokuDefault"
  description = "Name of the group, as the _monolithic template had it. Group names are unique per VPC, so a fixed name does not collide across copies of this project - each copy has its own VPC"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.name)) && !startswith(var.name, "sg-")
    error_message = "name must be 1-255 characters from the set EC2 accepts for a security group name (a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*, no apostrophe) and must not start with \"sg-\"."
  }
}
variable "description" {
  type        = string
  default     = "Security Group for Gomoku Resources"
  description = "Description of the group, as the _monolithic template had it. Changing it replaces the group (rules.md F-1)"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.description))
    error_message = "description must be 1-255 characters from the set EC2 accepts for a security group description: a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*. An apostrophe is not allowed."
  }
}
