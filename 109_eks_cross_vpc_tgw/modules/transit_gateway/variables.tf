variable "name" {
  type        = string
  default     = "cross-vpc-tgw"
  description = "Name tag of the gateway, and the prefix for its route table and attachment names"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,30}[a-z0-9]$", var.name))
    error_message = "name must be 3-32 lowercase letters, digits or hyphens and must not start or end with a hyphen."
  }
}

variable "description" {
  type        = string
  default     = "Routes traffic between the two EKS VPCs"
  description = "Description on the transit gateway"

  validation {
    condition     = length(var.description) > 0
    error_message = "description must not be empty."
  }
}

variable "attachments" {
  type = map(object({
    vpc_id     = string
    subnet_ids = list(string)
    cidr_block = string
  }))
  description = <<-DESC
    The VPCs on this gateway, keyed by a caller-chosen label.

    A map rather than a list because every value in it - the VPC ID, the subnet IDs - comes from another
    module and is unknown at plan time, while for_each needs keys it can determine during plan. The caller's
    labels supply them (rules.md B-8).

    The subnets have to be in a routable tier. An attachment in a non-routable subnet is created without
    complaint and then unreachable from the other side, which is a timeout rather than an error.
  DESC

  validation {
    condition     = length(var.attachments) >= 2
    error_message = "attachments must name at least two VPCs; a transit gateway with one attachment routes nothing."
  }
  validation {
    condition     = alltrue([for label in keys(var.attachments) : can(regex("^[a-zA-Z0-9._-]+$", label))])
    error_message = "attachments keys become part of a resource address and a Name tag, so each must be letters, digits, dots, underscores or hyphens."
  }
  validation {
    condition     = alltrue([for attachment in values(var.attachments) : length(attachment.subnet_ids) > 0])
    error_message = "every attachment needs at least one subnet."
  }
  validation {
    condition     = alltrue([for attachment in values(var.attachments) : can(cidrhost(attachment.cidr_block, 0))])
    error_message = "every attachment's cidr_block must be a valid IPv4 CIDR block - it is the destination the gateway routes to that VPC."
  }
}

variable "auto_accept_shared_attachments" {
  type        = string
  default     = "enable"
  description = "Whether attachments shared from another account are accepted without approval. Enabled, as the _monolithic template had it, and worth narrowing for anything beyond a demo: both VPCs here are in the same account, so nothing needs it"

  validation {
    condition     = contains(["enable", "disable"], var.auto_accept_shared_attachments)
    error_message = "auto_accept_shared_attachments must be either enable or disable."
  }
}
