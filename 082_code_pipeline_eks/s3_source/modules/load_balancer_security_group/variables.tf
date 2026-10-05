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
  default     = "alb-sg"
  description = "Name of the security group. Handed to the AWS Load Balancer Controller by ID through an Ingress or Service annotation, so the controller attaches this group instead of inventing its own"

  validation {
    condition     = length(var.name) > 0
    error_message = "name must not be empty."
  }
  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.name)) && !startswith(var.name, "sg-")
    error_message = "name must be 1-255 characters from the set AWS accepts for a security group name (a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*, no apostrophe) and must not start with \"sg-\", which EC2 reserves for security group IDs."
  }
}
variable "description" {
  type        = string
  default     = "Frontend security group for a load balancer managed by the AWS Load Balancer Controller"
  description = "Description attached to the security group"

  validation {
    condition     = length(var.description) > 0
    error_message = "description must not be empty."
  }
  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.description))
    error_message = "description must be 1-255 characters from the set AWS accepts for a security group description: a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*. An apostrophe is NOT allowed - EC2 rejects the CreateSecurityGroup call with InvalidParameterValue, which otherwise only surfaces at apply time."
  }
}
variable "ports" {
  type = map(number)
  default = {
    http = 80
  }
  description = "Listener ports opened for inbound traffic, keyed by a caller-chosen label that appears in the rule descriptions and resource addresses. A map rather than a single number because a load balancer fronting an ingress controller listens on more than one port: the controller's Service publishes http and https, the load balancer gets a listener for each, and a port missing here is a listener that accepts nothing while every Terraform resource still reports success"

  validation {
    condition     = length(var.ports) > 0
    error_message = "ports must contain at least one port - a load balancer whose security group opens nothing is unreachable."
  }
  validation {
    condition     = alltrue([for label in keys(var.ports) : can(regex("^[a-zA-Z0-9._-]+$", label))])
    error_message = "ports keys are labels used in the rule descriptions and resource addresses, so each must be a non-empty string of letters, digits, dots, underscores or hyphens. An apostrophe in a rule description is rejected by EC2 at apply time (rules.md F-1)."
  }
  validation {
    condition     = alltrue([for port in values(var.ports) : port > 0 && port <= 65535])
    error_message = "ports values must be valid TCP ports."
  }
}
variable "allow_inbound_from_anywhere" {
  type        = bool
  default     = false
  description = "Whether to allow inbound traffic on every port in ports from 0.0.0.0/0. Needed for an internet-facing load balancer that anyone should reach; leave false and use ingress_source_security_groups when only in-VPC callers (e.g. the bastion) should get through"
}
variable "ingress_cidr_blocks" {
  type        = list(string)
  default     = []
  description = "Specific CIDR blocks allowed inbound on every port in ports, for narrowing an internet-facing load balancer to known networks instead of opening it to 0.0.0.0/0"

  validation {
    condition     = alltrue([for cidr in var.ingress_cidr_blocks : can(cidrhost(cidr, 0))])
    error_message = "ingress_cidr_blocks must contain valid IPv4 CIDR blocks."
  }
}
variable "ingress_source_security_groups" {
  type        = map(string)
  default     = {}
  description = "Security group IDs allowed inbound on every port in ports, keyed by a caller-chosen label, e.g. { vscode_ec2 = module.vscode_ec2.security_group_id } so an internal load balancer is reachable from the bastion and nowhere else. The module is handed IDs and never looks the sources up itself (rules.md B-6). A map rather than a list because these IDs are usually another module's output, unknown until apply, and for_each needs statically known keys (rules.md B-8)"

  validation {
    condition     = alltrue([for label in keys(var.ingress_source_security_groups) : can(regex("^[a-zA-Z0-9._-]+$", label))])
    error_message = "ingress_source_security_groups keys are labels used in the rule descriptions and resource addresses, so each must be a non-empty string of letters, digits, dots, underscores or hyphens."
  }
  validation {
    condition     = alltrue([for id in values(var.ingress_source_security_groups) : can(regex("^sg-[0-9a-f]+$", id))])
    error_message = "ingress_source_security_groups must contain valid security group IDs (e.g. sg-0123456789abcdef0)."
  }
}
variable "revoke_rules_on_delete" {
  type        = bool
  default     = true
  description = "Whether to revoke every rule attached to the group before deleting it. True because the AWS Load Balancer Controller add rules to this group outside Terraform, and AWS refuses to delete a security group while rules referencing it still exist - which otherwise leaves terraform destroy blocked on a DependencyViolation"
}
