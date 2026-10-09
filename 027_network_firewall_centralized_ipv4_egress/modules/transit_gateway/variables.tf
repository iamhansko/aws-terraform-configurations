variable "name" {
  type        = string
  default     = "firewall-natgw-tgw"
  description = "Name tag of the transit gateway. The _monolithic template tagged nothing here, which leaves an untagged tgw-... in the console next to every other one in the account; the tag is added because a transit gateway is the one resource in this project that is easy to mistake for someone else's"

  validation {
    condition     = length(var.name) > 0
    error_message = "name must not be empty."
  }
}
variable "description" {
  type        = string
  default     = "Centralized IPv4 egress hub: spoke VPC to inspection VPC via a default static route"
  description = "Description of the transit gateway. The _monolithic template set none"

  validation {
    condition     = length(var.description) > 0
    error_message = "description must not be empty."
  }
}
variable "default_route_table_association" {
  type        = string
  default     = "enable"
  description = <<-DESC
    Whether new attachments are associated with the default route table automatically, as the _monolithic
    template set it.

    Enabled is what makes this project's single static route work at all. With it enabled both attachments
    land in the one default route table, so the 0.0.0.0/0 route the root adds there applies to traffic
    arriving from the spoke VPC. Disabling it and declaring no explicit association produces an attachment
    associated with nothing: the attachment reaches Available, the route is accepted, and traffic from the
    spoke is blackholed at the gateway with no error anywhere.

    A production hub usually disables this and uses one route table per segment - that is how spoke-to-
    spoke traffic is kept apart. With a single spoke there is nothing to keep apart.
  DESC

  validation {
    condition     = contains(["enable", "disable"], var.default_route_table_association)
    error_message = "default_route_table_association must be enable or disable."
  }
}
variable "default_route_table_propagation" {
  type        = string
  default     = "enable"
  description = <<-DESC
    Whether attachment CIDRs are propagated into the default route table automatically, as the _monolithic
    template set it.

    This is the return half. Propagation is what puts the spoke VPC's CIDR into the default route table, so
    a packet coming back from the egress VPC's attachment has somewhere to go. The static 0.0.0.0/0 route
    the root adds covers only the outbound direction; without propagation the reply reaches the gateway and
    is dropped there, which looks exactly like a firewall drop from the instance's point of view.
  DESC

  validation {
    condition     = contains(["enable", "disable"], var.default_route_table_propagation)
    error_message = "default_route_table_propagation must be enable or disable."
  }
}
variable "auto_accept_shared_attachments" {
  type        = string
  default     = "enable"
  description = "Whether attachment requests from other accounts are accepted without review, as the _monolithic template set it. Both attachments in this project are in the same account as the gateway, so this setting changes nothing here - and it is the one default worth narrowing before this configuration is used anywhere real, because enabled means any account the gateway is shared with can attach itself to a hub whose default route reaches the internet"

  validation {
    condition     = contains(["enable", "disable"], var.auto_accept_shared_attachments)
    error_message = "auto_accept_shared_attachments must be enable or disable."
  }
}
variable "dns_support" {
  type        = string
  default     = "enable"
  description = "Whether the gateway resolves public DNS hostnames to private addresses across attachments, as the _monolithic template set it. Unrelated to the firewall's DNS rules, which drop queries to port 53 - this setting is about resolution between attached VPCs, not about egress queries"

  validation {
    condition     = contains(["enable", "disable"], var.dns_support)
    error_message = "dns_support must be enable or disable."
  }
}
variable "vpn_ecmp_support" {
  type        = string
  default     = "enable"
  description = "Whether equal-cost multipath is used across VPN attachments, as the _monolithic template set it. There is no VPN attachment in this project, so it has no effect; it is kept as a variable rather than dropped because the original set it explicitly"

  validation {
    condition     = contains(["enable", "disable"], var.vpn_ecmp_support)
    error_message = "vpn_ecmp_support must be enable or disable."
  }
}
