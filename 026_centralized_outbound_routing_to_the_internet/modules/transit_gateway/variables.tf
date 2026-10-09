variable "name" {
  type        = string
  default     = "cross-vpc-tgw"
  description = "Name tag of the transit gateway. The _monolithic template's aws_ec2_transit_gateway block carried no tags at all, which leaves an unnamed tgw- id in the console"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,30}[a-z0-9]$", var.name))
    error_message = "name must be 3-32 lowercase letters, digits or hyphens and must not start or end with a hyphen."
  }
}
variable "description" {
  type        = string
  default     = "Carries all outbound traffic from the app VPC to the egress VPC"
  description = "Description on the transit gateway"

  validation {
    condition     = length(var.description) > 0
    error_message = "description must not be empty."
  }
}
variable "auto_accept_shared_attachments" {
  type        = string
  default     = "enable"
  description = "Whether attachments shared from another account are accepted without approval. Enabled, as the _monolithic template had it; both VPCs here are in the same account, so nothing in this project needs it"

  validation {
    condition     = contains(["enable", "disable"], var.auto_accept_shared_attachments)
    error_message = "auto_accept_shared_attachments must be either enable or disable."
  }
}
