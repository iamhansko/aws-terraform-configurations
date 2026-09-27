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
  default     = "pod-sg"
  description = "Name of the security group attached to every pod ENI"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.name)) && !startswith(var.name, "sg-")
    error_message = "name must use the character set EC2 accepts for a security group name (no apostrophe) and must not start with \"sg-\" (rules.md F-1)."
  }
}
variable "description" {
  type        = string
  default     = "Attached to pod ENIs created from the ENIConfigs, in the secondary CIDR"
  description = "Description attached to the security group"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.description))
    error_message = "description must be 1-255 characters from the set AWS accepts for a security group description: a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*. An apostrophe is NOT allowed - EC2 rejects CreateSecurityGroup with InvalidParameterValue, which otherwise only surfaces at apply time (rules.md F-1)."
  }
}
variable "cluster_security_group_id" {
  type        = string
  description = "The EKS cluster security group, which the control plane's network interfaces use. Needed as the source of the webhook rule below: the API server calls admission webhooks running in pods, and with custom networking those pods are on ENIs in this group rather than sharing the node's"

  validation {
    condition     = can(regex("^sg-[0-9a-f]+$", var.cluster_security_group_id))
    error_message = "cluster_security_group_id must be a valid security group ID."
  }
}
variable "webhook_port" {
  type        = number
  default     = 9443
  description = "Port the control plane reaches admission webhooks on. 9443 is the convention almost every controller follows, including the AWS Load Balancer Controller this project installs - without this rule its webhook times out and every Ingress create is rejected"

  validation {
    condition     = var.webhook_port > 0 && var.webhook_port <= 65535
    error_message = "webhook_port must be between 1 and 65535."
  }
}
variable "dns_port" {
  type        = number
  default     = 53
  description = "Port CoreDNS listens on. Allowed from this group to itself, because with custom networking the CoreDNS pods and their clients are all on ENIs in this group, so pod-to-pod DNS is intra-group traffic that would otherwise be denied"

  validation {
    condition     = var.dns_port > 0 && var.dns_port <= 65535
    error_message = "dns_port must be between 1 and 65535."
  }
}
variable "allow_all_self_traffic" {
  type        = bool
  default     = false
  description = "Whether to allow all protocols between members of this group instead of only DNS. False reproduces the _monolithic template, which allowed exactly TCP and UDP on the DNS port. True is worth setting the moment pods need to reach each other on anything else - otherwise that failure looks like an application problem rather than a security group one"
}
variable "revoke_rules_on_delete" {
  type        = bool
  default     = true
  description = "Whether to revoke this group's rules before deleting it. True because the AWS Load Balancer Controller adds backend rules to the groups in this cluster that Terraform does not track, and AWS refuses to delete a group while any rule still references it (rules.md F-2)"
}
