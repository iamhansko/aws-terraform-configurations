variable "vpc_id" {
  type        = string
  description = "VPC the security group is created in"

  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must be a valid VPC ID (e.g. vpc-0123456789abcdef0)."
  }
}

variable "name" {
  type        = string
  default     = "k8s-default-sg"
  description = "Name of the security group, as the _monolithic template named it"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.name)) && !startswith(var.name, "sg-")
    error_message = "name must be 1-255 characters from the set AWS accepts for a security group name (a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*, no apostrophe) and must not start with \"sg-\", which EC2 reserves for security group IDs."
  }
}

variable "description" {
  type        = string
  default     = "Shared security group for the kubeadm control plane, workers and workbench"
  description = "Description attached to the security group. Changing it replaces the group, and every instance referencing it with it, so it is worth getting right the first time (rules.md F-1)"

  validation {
    condition     = length(var.description) > 0
    error_message = "description must not be empty."
  }
  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.description))
    error_message = "description must be 1-255 characters from the set AWS accepts for a security group description: a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*. An apostrophe is NOT allowed - EC2 rejects the CreateSecurityGroup call with InvalidParameterValue, which otherwise only surfaces at apply time (rules.md F-1)."
  }
}

variable "ingress_source_security_groups" {
  type        = map(string)
  default     = {}
  description = "Additional security groups allowed all traffic inbound, keyed by a caller-chosen label that appears in the rule descriptions and resource addresses. A map rather than a list because these IDs are usually another module's output, unknown until apply, and for_each needs statically known keys (rules.md B-8)"

  validation {
    condition     = alltrue([for label in keys(var.ingress_source_security_groups) : can(regex("^[a-zA-Z0-9._-]+$", label))])
    error_message = "ingress_source_security_groups keys become part of a rule description, so each must be letters, digits, dots, underscores or hyphens - an apostrophe is rejected by EC2 at apply time (rules.md F-1)."
  }
  validation {
    condition     = alltrue([for id in values(var.ingress_source_security_groups) : can(regex("^sg-[0-9a-f]+$", id))])
    error_message = "ingress_source_security_groups must contain valid security group IDs (e.g. sg-0123456789abcdef0)."
  }
}

variable "revoke_rules_on_delete" {
  type        = bool
  default     = true
  description = "Whether Terraform revokes the group's attached rules before deleting it, including rules it did not create. AWS refuses to delete a group while anything references it, and this group references itself"
}
