variable "vpc_id" {
  type        = string
  description = "VPC the task security group is created in"

  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must be a valid VPC ID (e.g. vpc-0123456789abcdef0)."
  }
}
variable "name" {
  type        = string
  default     = "ecs-service-sg"
  description = "Name of the security group, as the _monolithic template had it. Unique within the VPC only, so two copies of the project in one account do not collide"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.name)) && !startswith(var.name, "sg-")
    error_message = "name must be 1-255 characters from the set AWS accepts for a security group name (a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*, no apostrophe) and must not start with \"sg-\", which EC2 reserves for security group IDs."
  }
}
variable "description" {
  type        = string
  default     = "Security group for the ECS task ENIs"
  description = "Description attached to the security group. The _monolithic template had \"Security Group\". Changing it replaces the group, and EC2 refuses to delete the old one with DependencyViolation while a task ENI still carries it (rules.md F-1)"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.description))
    error_message = "description must be 1-255 characters from the set AWS accepts for a security group description: a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*. An apostrophe is NOT allowed - EC2 rejects the CreateSecurityGroup call with InvalidParameterValue, which otherwise only surfaces at apply time (rules.md F-1)."
  }
}
variable "self_ingress_ports" {
  type        = list(number)
  default     = []
  description = "TCP ports members of this group may reach each other on - the container ports of the tasks that other tasks call. The caller passes the same value it gives the task definition (rules.md B-5). Empty creates no ingress rule"

  validation {
    condition     = alltrue([for port in var.self_ingress_ports : port >= 1 && port <= 65535 && floor(port) == port])
    error_message = "self_ingress_ports entries must be integers between 1 and 65535."
  }

  validation {
    condition     = length(distinct(var.self_ingress_ports)) == length(var.self_ingress_ports)
    error_message = "self_ingress_ports must not repeat a port."
  }
}
