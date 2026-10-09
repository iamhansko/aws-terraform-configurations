locals {
  # The Suricata rules, built from the protocol list instead of being two literal lines as in the
  # _monolithic template. Rendering them makes the signature ids derived rather than hand-numbered,
  # which matters because Suricata rejects a duplicate sid - and it rejects it when the rule group is
  # created, so the failure is an apply-time parse error on this resource rather than anything a plan
  # would show.
  stateful_rules = join("\n", [
    for index, protocol in var.blocked_dns_protocols :
    "drop ${protocol} any any -> any ${var.blocked_dns_port} (msg:\"Drop DNS ${upper(protocol)} egress\"; sid:${var.stateful_rule_sid_base + index};)"
  ])
  # Trailing newline, as the _monolithic template's string had. Suricata tolerates its absence; it is
  # kept so a diff against the original shows nothing here.
  stateful_rules_string = "${local.stateful_rules}\n"

  # Which log types go to CloudWatch, as a set so the log groups and the destination configs below
  # are generated from one list. Empty when logging is off, which leaves no groups to delete.
  log_types = var.enable_logging ? toset(["FLOW", "ALERT"]) : toset([])
}
# Drops ICMP, both directions, any address to any address - exactly the _monolithic template's rule.
#
# Stateless rather than stateful because ICMP has no connection to track, and the stateless engine
# sees every packet first. The policy's default action forwards everything else to the stateful
# engine, so this group is the only thing that can drop a packet before the Suricata rules run.
resource "aws_networkfirewall_rule_group" "stateless_icmp_block" {
  name     = "${var.name}-icmp-block-stateless"
  type     = "STATELESS"
  capacity = var.rule_group_capacity
  rule_group {
    rules_source {
      stateless_rules_and_custom_actions {
        stateless_rule {
          priority = 1
          rule_definition {
            actions = ["aws:drop"]
            match_attributes {
              source {
                address_definition = var.any_source_cidr_block
              }
              destination {
                address_definition = var.any_source_cidr_block
              }
              protocols = [var.blocked_icmp_protocol_number]
            }
          }
        }
      }
    }
  }
}
# Drops DNS leaving the VPC, over UDP and TCP - the _monolithic template's two rules_string lines.
#
# Worth being precise about what this can and cannot block, because the obvious test is misleading.
# A host in either VPC resolves names through the Amazon-provided resolver at the VPC+2 address, and
# that query is answered inside the VPC: it never reaches a route table that could send it to the
# transit gateway, so it never reaches this firewall. Ordinary name resolution therefore keeps
# working no matter what this group says. What the rule is aimed at is a host configured to query a
# resolver outside the VPC - "dig @8.8.8.8" - which is the probe the root's outputs tell someone to
# run.
resource "aws_networkfirewall_rule_group" "stateful_dns_block" {
  name     = "${var.name}-dns-block-stateful"
  type     = "STATEFUL"
  capacity = var.rule_group_capacity
  rule_group {
    rules_source {
      rules_string = local.stateful_rules_string
    }
  }
}
resource "aws_networkfirewall_firewall_policy" "firewall_policy" {
  name = "${var.name}-policy"
  firewall_policy {
    stateless_rule_group_reference {
      resource_arn = aws_networkfirewall_rule_group.stateless_icmp_block.arn
      priority     = 1
    }
    stateful_rule_group_reference {
      resource_arn = aws_networkfirewall_rule_group.stateful_dns_block.arn
    }
    # forward_to_sfe on both, as the _monolithic template had it: anything the stateless group did
    # not drop is handed to the stateful engine. The alternative defaults - aws:pass or aws:drop -
    # would make the Suricata rules above unreachable or would drop everything, and in both cases the
    # firewall would still report itself as ready.
    stateless_default_actions          = ["aws:forward_to_sfe"]
    stateless_fragment_default_actions = ["aws:forward_to_sfe"]
  }
}
# The firewall, and the finding this whole project turns on.
#
# IT INSPECTS NOTHING. Both endpoints are created, both report ready, both bill per hour, and not one
# packet reaches either of them. This reproduces the _monolithic template rather than diverging from
# it, and it is written down here because no status check anywhere in AWS reports it.
#
# Why: a Network Firewall endpoint only sees traffic that a route table sends to it, by naming the
# endpoint's vpc_endpoint_id as a route target. The _monolithic template wrote six routes and none of
# them names an endpoint, and it associated no route table with the firewall subnets at all - so
# those subnets sit on the VPC's main table, holding only the local route. The egress path the
# template actually built is:
#
#   app instance -> app route table (0.0.0.0/0 -> tgw) -> transit gateway
#     -> egress VPC attachment subnet -> attachment route table (0.0.0.0/0 -> NAT)
#     -> NAT gateway in the public subnet -> public route table (0.0.0.0/0 -> IGW) -> internet
#
# The firewall subnets are not on that path. Both rule groups above are therefore unreachable, which
# is directly testable: with the firewall supposedly dropping ICMP and external DNS, a ping and a
# "dig @8.8.8.8" from the app VPC both succeed. Those two probes are in the root's outputs for that
# reason - they are the demonstration, and today they demonstrate the gap.
#
# What would close it, if this project is ever meant to inspect rather than to show the topology.
# Three changes, and all three are needed - any one alone produces a worse failure than the current
# one, because a half-inserted firewall blackholes traffic instead of passing it:
#
#   1. Attachment subnet route tables: repoint 0.0.0.0/0 from the NAT gateway to the firewall
#      endpoint in the same zone (vpc_endpoint_id, from endpoint_ids_by_zone below).
#   2. A route table per firewall subnet, associated with it, carrying 0.0.0.0/0 to that zone's NAT
#      gateway and the app VPC's CIDR back to the transit gateway. The firewall subnets have no table
#      at all today.
#   3. The public route table, which currently sends the app VPC's CIDR straight to the transit
#      gateway, has to send it to the firewall endpoint instead so replies are inspected too - and it
#      must become one table per zone to do that. A firewall endpoint is zonal, so a single shared
#      public table can only name one of them, and the zone that gets the wrong one has its return
#      traffic inspected by a different endpoint than its outbound. Network Firewall's stateful
#      engine sees half of such a flow and drops it, which looks exactly like an application problem.
#
# None of that is done here. It is a different topology from the one the template describes, it
# cannot be verified without applying a firewall that bills by the hour, and an untested inspection
# path that silently drops asymmetric flows would replace a documented gap with an undocumented one.
resource "aws_networkfirewall_firewall" "network_firewall" {
  name   = var.name
  vpc_id = var.vpc_id
  # .arn rather than the _monolithic file's .id. For this resource the provider sets id to the ARN, so
  # the two are the same string today; naming the attribute that is documented to be an ARN means a
  # provider that ever stops conflating them does not break this silently.
  firewall_policy_arn = aws_networkfirewall_firewall_policy.firewall_policy.arn

  # One endpoint per zone, generated from the map so adding a zone is a map entry. The _monolithic
  # template wrote two subnet_mapping blocks out by hand.
  dynamic "subnet_mapping" {
    for_each = var.subnet_ids
    content {
      subnet_id = subnet_mapping.value
    }
  }

  delete_protection                 = var.delete_protection
  subnet_change_protection          = var.subnet_change_protection
  firewall_policy_change_protection = var.firewall_policy_change_protection
  tags = {
    Name = var.name
  }
}
# Logging, which the _monolithic template did not configure.
#
# Added because a firewall nobody can observe cannot be told apart from a firewall nobody is using,
# and this project is the second case. With the routing above, the FLOW log group stays empty
# forever - which is the cleanest available proof of the note on the firewall resource, and is
# unavailable without a logging configuration to look at.
resource "aws_cloudwatch_log_group" "firewall" {
  for_each = local.log_types

  name              = "/aws/network-firewall/${var.name}/${lower(each.key)}"
  retention_in_days = var.log_retention_days
  tags = {
    Name = "${var.name}-${lower(each.key)}"
  }
}
resource "aws_networkfirewall_logging_configuration" "firewall" {
  count = var.enable_logging ? 1 : 0

  firewall_arn = aws_networkfirewall_firewall.network_firewall.arn
  logging_configuration {
    dynamic "log_destination_config" {
      for_each = local.log_types
      content {
        log_type             = log_destination_config.key
        log_destination_type = "CloudWatchLogs"
        # logGroup, camelCase, is the key Network Firewall's API expects in this free-form map. A
        # snake_case key is accepted by Terraform and rejected by the service with
        # InvalidRequestException, which is an apply-time failure a plan cannot catch.
        log_destination = {
          logGroup = aws_cloudwatch_log_group.firewall[log_destination_config.key].name
        }
      }
    }
  }
}
