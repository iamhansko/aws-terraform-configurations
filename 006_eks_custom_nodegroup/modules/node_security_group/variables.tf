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
  default     = "eks-node-sg"
  description = "Name of the security group shared by the cluster's managed ENIs and the worker nodes"

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
  default     = "Shared security group for EKS worker nodes and the EKS-managed network interfaces"
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
variable "ingress_source_security_groups" {
  type        = map(string)
  default     = {}
  description = "Additional security group IDs allowed to send any traffic to members of this group, keyed by a caller-chosen label, on top of the self-referencing rule. Used to let a bastion reach the API server endpoint the cluster exposes through this group. A map rather than a list because these IDs are usually another module's output, unknown until apply, and for_each needs statically known keys (rules.md B-8)"

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
  description = "Whether to revoke every rule attached to the group before deleting it. True because the AWS Load Balancer Controller (backend rules) and EKS (control-plane-to-node rules) add rules to this group outside Terraform, and AWS refuses to delete a security group while rules referencing it still exist - which otherwise leaves terraform destroy blocked on a DependencyViolation"
}
