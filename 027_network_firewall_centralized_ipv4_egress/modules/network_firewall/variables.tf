variable "vpc_id" {
  type        = string
  description = "VPC the firewall is created in. This is the firewall's primary VPC and cannot be changed afterwards - the provider marks vpc_id as forcing replacement, and replacing a firewall means both endpoints are destroyed and recreated, which breaks every route pointing at them until the new ids are written back"

  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must be a valid VPC ID (e.g. vpc-0123456789abcdef0)."
  }
}
variable "firewall_subnet_a_id" {
  type        = string
  description = "Dedicated firewall subnet in the first availability zone. Taken as an id rather than looked up here so this module does not have to know how the egress VPC is laid out (rules.md B-6), and taken as two separate variables rather than a list so the endpoint outputs can be matched back to the zone the caller meant"

  validation {
    condition     = can(regex("^subnet-[0-9a-f]+$", var.firewall_subnet_a_id))
    error_message = "firewall_subnet_a_id must be a valid subnet ID (e.g. subnet-0123456789abcdef0)."
  }
}
variable "firewall_subnet_b_id" {
  type        = string
  description = "Dedicated firewall subnet in the second availability zone. Must be in a different zone from firewall_subnet_a_id - Network Firewall requires one subnet mapping per zone and rejects two in the same zone"

  validation {
    condition     = can(regex("^subnet-[0-9a-f]+$", var.firewall_subnet_b_id))
    error_message = "firewall_subnet_b_id must be a valid subnet ID (e.g. subnet-0123456789abcdef0)."
  }
  validation {
    condition     = var.firewall_subnet_b_id != var.firewall_subnet_a_id
    error_message = "firewall_subnet_b_id must differ from firewall_subnet_a_id. A subnet hosts at most one firewall endpoint, so the same subnet twice is rejected, and the two endpoint outputs would be the same endpoint - sending both zones' traffic across one zone boundary."
  }
}
variable "firewall_name" {
  type        = string
  default     = "firewall"
  description = "Name of the firewall, as the _monolithic template named it. It cannot be changed after creation (the provider forces replacement), and it is the handle every describe-firewall call in the outputs uses"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{1,128}$", var.firewall_name))
    error_message = "firewall_name must be 1-128 characters of letters, digits and hyphens - the character set AWS accepts for a firewall name. Anything else is rejected at apply by the CreateFirewall call, not at plan."
  }
}
variable "firewall_policy_name" {
  type        = string
  default     = "firewall-policy"
  description = "Name of the firewall policy, as the _monolithic template named it"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{1,128}$", var.firewall_policy_name))
    error_message = "firewall_policy_name must be 1-128 characters of letters, digits and hyphens."
  }
}
variable "ip_address_type" {
  type        = string
  default     = "IPV4"
  description = "Address family of the firewall endpoints. IPV4, which is the default the _monolithic template relied on for the firewall's own subnet mappings and set explicitly on the endpoint associations it also declared. This project is IPv4-only end to end - the NAT gateways, the routes and the rule groups all are - so DUALSTACK here would create endpoints with an IPv6 address nothing routes to"

  validation {
    condition     = contains(["IPV4", "DUALSTACK"], var.ip_address_type)
    error_message = "ip_address_type must be IPV4 or DUALSTACK."
  }
}
variable "stateless_rule_group_name" {
  type        = string
  default     = "icmp-block-stateless"
  description = "Name of the stateless rule group, as the _monolithic template named it"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{1,128}$", var.stateless_rule_group_name))
    error_message = "stateless_rule_group_name must be 1-128 characters of letters, digits and hyphens."
  }
}
variable "stateless_rule_group_capacity" {
  type        = number
  default     = 100
  description = "Reserved capacity of the stateless rule group, as the _monolithic template set it. Capacity is fixed at creation and cannot be raised - the provider forces replacement - so it is set well above what one rule needs. A stateless rule's cost is the product of its match settings, which for the single rule here is small"

  validation {
    condition     = var.stateless_rule_group_capacity >= 1 && var.stateless_rule_group_capacity <= 30000
    error_message = "stateless_rule_group_capacity must be between 1 and 30000, the range AWS accepts for a stateless rule group."
  }
}
variable "stateless_rule_priority" {
  type        = number
  default     = 1
  description = "Priority of the single stateless rule inside its group, as the _monolithic template set it. Stateless rules are evaluated in ascending priority and the first match wins, so this only matters once a second rule is added"

  validation {
    condition     = var.stateless_rule_priority >= 1 && var.stateless_rule_priority <= 65535
    error_message = "stateless_rule_priority must be between 1 and 65535."
  }
}
variable "stateless_rule_group_priority" {
  type        = number
  default     = 1
  description = "Priority of the stateless rule group inside the policy, as the _monolithic template set it"

  validation {
    condition     = var.stateless_rule_group_priority >= 1 && var.stateless_rule_group_priority <= 65535
    error_message = "stateless_rule_group_priority must be between 1 and 65535."
  }
}
variable "blocked_stateless_protocols" {
  type        = list(number)
  default     = [1]
  description = <<-DESC
    IANA protocol numbers the stateless rule drops, as the _monolithic template set them: [1], which is
    ICMP.

    Protocol numbers rather than names, because that is what the API takes. 1 is ICMP, and dropping it
    statelessly is what makes "ping 1.1.1.1" from the spoke instance hang rather than answer - the visible
    half of this demo that does not need a log to observe.

    Stateless rather than stateful on purpose: a stateless drop costs nothing to evaluate and needs no flow
    state, and ICMP echo is exactly the kind of traffic there is no point handing to the stateful engine.
  DESC

  validation {
    condition     = length(var.blocked_stateless_protocols) > 0 && alltrue([for protocol in var.blocked_stateless_protocols : protocol >= 0 && protocol <= 255])
    error_message = "blocked_stateless_protocols must be a non-empty list of IANA protocol numbers between 0 and 255 (1 is ICMP, 6 TCP, 17 UDP)."
  }
}
variable "stateless_source_address" {
  type        = string
  default     = "0.0.0.0/0"
  description = "Source CIDR the stateless rule matches, as the _monolithic template set it. Any source, because every packet reaching this firewall has already been selected by a route table - the firewall sees spoke traffic and nothing else"

  validation {
    condition     = can(cidrhost(var.stateless_source_address, 0))
    error_message = "stateless_source_address must be a valid IPv4 CIDR block."
  }
}
variable "stateless_destination_address" {
  type        = string
  default     = "0.0.0.0/0"
  description = "Destination CIDR the stateless rule matches, as the _monolithic template set it"

  validation {
    condition     = can(cidrhost(var.stateless_destination_address, 0))
    error_message = "stateless_destination_address must be a valid IPv4 CIDR block."
  }
}
variable "stateless_rule_actions" {
  type        = list(string)
  default     = ["aws:drop"]
  description = "Action the stateless rule takes on a match, as the _monolithic template set it. aws:drop discards the packet silently, which is why a blocked ping times out instead of reporting unreachable"

  validation {
    condition     = length(var.stateless_rule_actions) > 0 && alltrue([for action in var.stateless_rule_actions : contains(["aws:pass", "aws:drop", "aws:forward_to_sfe"], action)])
    error_message = "stateless_rule_actions entries must be aws:pass, aws:drop or aws:forward_to_sfe. A custom action name is also valid to the API but only when the group declares it, which this module does not."
  }
}
variable "stateful_rule_group_name" {
  type        = string
  default     = "dns-block-stateful"
  description = "Name of the stateful rule group, as the _monolithic template named it"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{1,128}$", var.stateful_rule_group_name))
    error_message = "stateful_rule_group_name must be 1-128 characters of letters, digits and hyphens."
  }
}
variable "stateful_rule_group_capacity" {
  type        = number
  default     = 100
  description = "Reserved capacity of the stateful rule group, as the _monolithic template set it. For a Suricata-format group this is the maximum number of rules, fixed at creation; the two rules below leave room to experiment without replacing the group"

  validation {
    condition     = var.stateful_rule_group_capacity >= 1 && var.stateful_rule_group_capacity <= 30000
    error_message = "stateful_rule_group_capacity must be between 1 and 30000."
  }
}
variable "stateful_rules_string" {
  type        = string
  default     = <<-RULES
    drop udp any any -> any 53 (msg:"Drop DNS UDP egress"; sid:1000001;)
    drop tcp any any -> any 53 (msg:"Drop DNS TCP egress"; sid:1000002;)
  RULES
  description = <<-DESC
    Suricata rules for the stateful engine, as the _monolithic template wrote them: drop DNS to port 53
    over both UDP and TCP.

    These say "any any -> any 53" rather than "$HOME_NET any -> $EXTERNAL_NET 53", and that is what makes
    them work in a centralized deployment. HOME_NET defaults to the CIDR of the VPC the firewall is in -
    the egress VPC's 10.0.0.0/16 here - so a rule written against $HOME_NET would never match traffic
    sourced from the spoke VPC's 172.16.0.0/16. AWS's own multi-VPC whitepaper lists overriding HOME_NET
    with every attached spoke CIDR as a key consideration for exactly this reason. Nothing in this module
    overrides it, because nothing in these rules refers to it; adding a rule that does means adding the
    policy-level variable too, and the symptom of forgetting is a rule that is loaded, reports no error and
    matches nothing.

    What this demonstrates, in combination with the spoke VPC leaving enable_dns_support true: a query to
    the Amazon resolver inside the VPC still works, because it matches the VPC's local route and never
    reaches the firewall, while "dig @8.8.8.8" leaves through the transit gateway and is dropped here. The
    two side by side are what show the firewall is in the path at all.

    Every rule needs a unique sid. A duplicate is rejected by the create with a Suricata parse error at
    apply time, which plan cannot see.
  DESC

  validation {
    condition     = length(trimspace(var.stateful_rules_string)) > 0
    error_message = "stateful_rules_string must not be empty. An empty rules_source fails the CreateRuleGroup call at apply."
  }
  validation {
    # Not a parser - it only catches the rule that was pasted in without one, which is the common way to
    # fail this. A real syntax error still only surfaces at apply.
    condition     = can(regex("sid:[0-9]+", var.stateful_rules_string))
    error_message = "stateful_rules_string must contain at least one sid: option. Suricata requires every rule to carry a unique sid, and a rule without one is rejected by CreateRuleGroup at apply time rather than at plan."
  }
}
variable "stateless_default_actions" {
  type        = list(string)
  default     = ["aws:forward_to_sfe"]
  description = "What the policy does with a packet no stateless rule matched, as the _monolithic template set it. aws:forward_to_sfe hands it to the stateful engine, which is what makes the DNS rules apply to anything at all - aws:pass here would let every packet past without the stateful engine ever seeing it, and the firewall would log nothing while appearing healthy"

  validation {
    condition     = length(var.stateless_default_actions) > 0 && alltrue([for action in var.stateless_default_actions : contains(["aws:pass", "aws:drop", "aws:forward_to_sfe"], action)])
    error_message = "stateless_default_actions entries must be aws:pass, aws:drop or aws:forward_to_sfe."
  }
}
variable "stateless_fragment_default_actions" {
  type        = list(string)
  default     = ["aws:forward_to_sfe"]
  description = "The same decision for IP fragments, as the _monolithic template set it. Fragments are handled separately because a fragment after the first carries no port numbers, so most stateless match attributes cannot apply to it"

  validation {
    condition     = length(var.stateless_fragment_default_actions) > 0 && alltrue([for action in var.stateless_fragment_default_actions : contains(["aws:pass", "aws:drop", "aws:forward_to_sfe"], action)])
    error_message = "stateless_fragment_default_actions entries must be aws:pass, aws:drop or aws:forward_to_sfe."
  }
}
variable "delete_protection" {
  type        = bool
  default     = false
  description = "Whether the firewall refuses to be deleted, as the _monolithic template set it. False, which is right for a demo that is torn down - true would make terraform destroy fail with InvalidOperationException and leave a firewall billing by the hour until the flag is cleared by hand"
}
variable "subnet_change_protection" {
  type        = bool
  default     = false
  description = "Whether the firewall refuses changes to its subnet mappings, as the _monolithic template set it"
}
variable "firewall_policy_change_protection" {
  type        = bool
  default     = false
  description = "Whether the firewall refuses to have its policy association changed, as the _monolithic template set it"
}
variable "log_types" {
  type        = set(string)
  default     = ["ALERT", "FLOW"]
  description = <<-DESC
    Firewall log types delivered to CloudWatch Logs. An empty set creates no log groups and no logging
    configuration.

    This whole capability is an addition - the _monolithic template configured no logging at all - and it
    is the one addition this project cannot do without. A firewall with no logging is indistinguishable
    from no firewall: the ping that times out and the dig that hangs look the same whether they were
    dropped by the firewall, by a missing route, or by a security group with no egress rule. ALERT records
    what the rules dropped; FLOW records every connection that passed, which is how you see that the
    traffic which succeeded went through the firewall rather than around it.

    TLS is not accepted here. It is a valid log type to the API but only for a policy with a TLS inspection
    configuration, which this one has none of, and the logging configuration is rejected at apply.
  DESC

  validation {
    condition     = alltrue([for log_type in var.log_types : contains(["ALERT", "FLOW"], log_type)])
    error_message = "log_types entries must be ALERT or FLOW. TLS requires a TLS inspection configuration on the firewall policy, which this module does not create, and is rejected by UpdateLoggingConfiguration at apply."
  }
}
variable "log_group_name_prefix" {
  type        = string
  default     = "/aws/network-firewall"
  description = "Prefix of the CloudWatch log group names; the firewall name and the lowercased log type are appended, giving /aws/network-firewall/firewall/alert"

  validation {
    condition     = can(regex("^/[a-zA-Z0-9_./#-]*[a-zA-Z0-9_#-]$", var.log_group_name_prefix))
    error_message = "log_group_name_prefix must start with a slash, must not end with one, and may contain only the characters CloudWatch Logs accepts in a group name (letters, digits, underscore, hyphen, slash, period, hash)."
  }
}
variable "log_retention_days" {
  type        = number
  default     = 7
  description = "Retention of the firewall log groups. The default is short because these groups receive a line per connection - FLOW logging on a busy egress path is the expensive half of this feature, and nothing in a demo needs last month's flows"

  validation {
    condition     = contains([0, 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be one of the values CloudWatch Logs accepts (0 for never expire, or 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653)."
  }
}
