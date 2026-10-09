variable "name" {
  type        = string
  default     = "firewall"
  description = "Name of the firewall, as the _monolithic template had it. The policy and the two rule groups derive their names from it instead of carrying the template's separate literals (firewall-policy, icmp-block-stateless, dns-block-stateful)"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{1,100}$", var.name))
    error_message = "name must be 1-100 characters of letters, digits and hyphens; the rule group names are derived from it and Network Firewall caps those at 128."
  }
}
variable "vpc_id" {
  type        = string
  description = "VPC the firewall is created in. Injected rather than looked up, so this module never learns which module built the VPC (rules.md B-6)"

  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must be a valid VPC ID (e.g. vpc-0123456789abcdef0)."
  }
}
variable "subnet_ids" {
  type        = map(string)
  description = <<-DESC
    Subnets to place a firewall endpoint in, keyed by zone suffix.

    A map rather than a list because the subnet IDs come from another module and are unknown during
    plan, while the subnet_mapping blocks are generated with a dynamic block - and a dynamic block's
    for_each has the same plan-known-keys requirement a resource's does (rules.md B-8). The caller's
    zone suffixes supply the keys.

    One endpoint per zone, and each one only ever handles traffic from route tables in its own zone.
    AWS allows nothing but the endpoint in a firewall subnet.
  DESC

  validation {
    condition     = length(var.subnet_ids) >= 1
    error_message = "subnet_ids must name at least one subnet; a firewall with no endpoint has nowhere to inspect traffic."
  }
  validation {
    condition     = alltrue([for suffix in keys(var.subnet_ids) : can(regex("^[a-zA-Z0-9._-]+$", suffix))])
    error_message = "subnet_ids keys become part of a resource address, so each must be letters, digits, dots, underscores or hyphens."
  }
  validation {
    condition     = alltrue([for id in values(var.subnet_ids) : can(regex("^subnet-[0-9a-f]+$", id))])
    error_message = "subnet_ids must contain valid subnet IDs (e.g. subnet-0123456789abcdef0)."
  }
}
variable "rule_group_capacity" {
  type        = number
  default     = 100
  description = "Reserved capacity for each rule group, as the _monolithic template had it. Capacity cannot be changed in place: raising it replaces the rule group, and the policy referencing it is updated rather than replaced, so the firewall itself survives"

  validation {
    condition     = var.rule_group_capacity >= 1 && var.rule_group_capacity <= 30000
    error_message = "rule_group_capacity must be between 1 and 30000."
  }
}
variable "blocked_icmp_protocol_number" {
  type        = number
  default     = 1
  description = "IP protocol number the stateless rule group drops, as the _monolithic template's protocols = [1] had it. 1 is ICMP, so this is the rule that would make a ping from the app VPC fail"

  validation {
    condition     = var.blocked_icmp_protocol_number >= 0 && var.blocked_icmp_protocol_number <= 255
    error_message = "blocked_icmp_protocol_number must be an IP protocol number between 0 and 255."
  }
}
variable "blocked_dns_port" {
  type        = number
  default     = 53
  description = "Destination port the stateful rule group drops, as the _monolithic template's rules_string had it"

  validation {
    condition     = var.blocked_dns_port > 0 && var.blocked_dns_port <= 65535
    error_message = "blocked_dns_port must be a valid TCP/UDP port."
  }
}
variable "blocked_dns_protocols" {
  type        = list(string)
  default     = ["udp", "tcp"]
  description = "Transport protocols the stateful rule group drops on blocked_dns_port. Both, as the _monolithic template's two rules_string lines had them - UDP alone would leave a resolver that falls back to TCP working"

  validation {
    condition     = length(var.blocked_dns_protocols) > 0
    error_message = "blocked_dns_protocols must name at least one protocol; an empty rules_string is rejected by Network Firewall."
  }
  validation {
    condition     = alltrue([for protocol in var.blocked_dns_protocols : contains(["udp", "tcp"], protocol)])
    error_message = "blocked_dns_protocols entries must be udp or tcp - they are written into a Suricata rule, which names the protocol in lowercase."
  }
}
variable "stateful_rule_sid_base" {
  type        = number
  default     = 1000001
  description = "First Suricata signature id, incremented per protocol. The _monolithic template used 1000001 and 1000002 literally; derived here so adding a protocol cannot collide. Suricata rejects a rules_string with a duplicate sid, which fails the apply on the rule group with a parse error rather than at plan"

  validation {
    condition     = var.stateful_rule_sid_base >= 1000000
    error_message = "stateful_rule_sid_base should be 1000000 or above; lower ranges are reserved for distributed rule sets."
  }
}
variable "any_source_cidr_block" {
  type        = string
  default     = "0.0.0.0/0"
  description = "Source and destination the stateless ICMP rule matches, as the _monolithic template's address_definition had it on both sides"

  validation {
    condition     = can(cidrhost(var.any_source_cidr_block, 0))
    error_message = "any_source_cidr_block must be a valid IPv4 CIDR block."
  }
}
variable "delete_protection" {
  type        = bool
  default     = false
  description = "Whether AWS refuses to delete the firewall. False, as the _monolithic template had it. A Network Firewall bills per hour from the moment it is created, so turning this on means a terraform destroy that fails partway through and leaves it billing"
}
variable "subnet_change_protection" {
  type        = bool
  default     = false
  description = "Whether AWS refuses to change the firewall's subnets. False, as the _monolithic template had it"
}
variable "firewall_policy_change_protection" {
  type        = bool
  default     = false
  description = "Whether AWS refuses to change which policy the firewall uses. False, as the _monolithic template had it"
}
variable "enable_logging" {
  type        = bool
  default     = true
  description = "Whether to deliver FLOW and ALERT logs to CloudWatch Logs. On, and an addition - the _monolithic template configured no logging. It is the only way to see whether the firewall receives any traffic at all, which is the question the note above aws_networkfirewall_firewall exists to answer"
}
variable "log_retention_days" {
  type        = number
  default     = 7
  description = "Retention on the firewall's log groups, so a forgotten deployment stops accruing storage. The groups are Terraform resources either way, so destroy removes them"

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be one of the retention periods CloudWatch Logs accepts (1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653)."
  }
}
