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
  default     = "eks-cluster-sg"
  description = "Name of the security group, as the _monolithic template had it"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.name)) && !startswith(var.name, "sg-")
    error_message = "name must be 1-255 characters from the set AWS accepts for a security group name (a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*, no apostrophe) and must not start with \"sg-\", which EC2 reserves for security group IDs."
  }
}
variable "description" {
  type        = string
  default     = "Shared by every EKS cluster in this project and by the bastion, so one group membership reaches all of them"
  description = "Description attached to the security group"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.description))
    error_message = "description must be 1-255 characters from the set AWS accepts for a security group description: a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*. An apostrophe is NOT allowed - EC2 rejects the CreateSecurityGroup call with InvalidParameterValue, which otherwise only surfaces at apply time (rules.md F-1)."
  }
}
variable "revoke_rules_on_delete" {
  type        = bool
  default     = true
  description = "Whether to revoke the group's rules before deleting it. True because EKS leaves rules on this group that Terraform does not track, and AWS refuses to delete a group while any rule references it (rules.md F-2)"
}
