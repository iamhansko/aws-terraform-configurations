# AWS Network Firewall: two rule groups, a policy, the firewall with one endpoint per availability zone,
# and the CloudWatch log groups that make any of it observable.
#
# The firewall endpoint is a route table target, not a device traffic finds on its own. It does not
# translate addresses and it does not appear in any path unless a route names it, which is why the whole
# project is really about the route tables in the egress VPC module and the root - this module's job is to
# produce two endpoint ids and tell the caller which zone each belongs to.
#
#
# Why the two aws_networkfirewall_vpc_endpoint_association resources are gone
# ---------------------------------------------------------------------------
# The _monolithic template declared the firewall with subnet_mapping blocks for both firewall subnets -
# which already creates one endpoint per subnet - and then declared two
# aws_networkfirewall_vpc_endpoint_association resources pointing at the *same two subnets*. The two
# attachment route tables then routed 0.0.0.0/0 at those associations. All three parts of that are wrong,
# and they fail in different ways:
#
#   1. The route target was the wrong identifier. A route's vpc_endpoint_id has to be a vpce-... endpoint
#      id. The template passed vpc_endpoint_association_id, which is the id of the association record, not
#      of the endpoint it created - CloudFormation exposes the two as separate attributes
#      (VpcEndpointAssociationId and EndpointId) for precisely that reason. validate and plan both pass,
#      because any string is acceptable to the attribute, and the CreateRoute call fails at apply.
#
#   2. The subnets were already in use. AWS's documented requirement for a same-account association is a
#      different subnet in the primary VPC, or a different VPC; a subnet hosts at most one firewall
#      endpoint, and the subnet named by a firewall's own subnet mapping is not available to host another.
#
#   3. Even if 1 and 2 were repaired by giving the associations two more dedicated subnets, the result
#      would be four firewall endpoints where the routing needs two. A firewall endpoint bills by the hour
#      per availability zone endpoint, so that is double the running cost of the most expensive resource in
#      the project, for no change in behaviour.
#
# What the associations were actually working around is worth recording, because it is a CloudFormation
# limitation rather than a mistake. AWS::NetworkFirewall::Firewall returns its endpoints as EndpointIds, a
# list of "zone:vpce-id" strings that the documentation explicitly says is in no particular order - so
# there is no safe way to select "the endpoint in zone a" from it with Fn::Select. The association resource
# does expose a single EndpointId, so declaring one per subnet was a way to get a routable id per zone.
#
# Terraform has no such limitation: firewall_status[0].sync_states carries availability_zone and
# attachment[0].subnet_id alongside attachment[0].endpoint_id, so the endpoint for a given subnet can be
# looked up directly. That is what the locals block below does, and it is the same kind of substitution as
# the Lambda the transit_gateway module deleted - a CloudFormation workaround that Terraform does not need.
#
# The resource type itself is not useless; it is how one firewall protects several VPCs, and how a VPC gets
# a second endpoint in one zone. Neither applies here: there is one VPC to inspect and one endpoint per
# zone is what the route tables can use.
resource "aws_networkfirewall_rule_group" "firewall_stateless_icmp_block" {
  name     = var.stateless_rule_group_name
  type     = "STATELESS"
  capacity = var.stateless_rule_group_capacity
  rule_group {
    rules_source {
      stateless_rules_and_custom_actions {
        stateless_rule {
          priority = var.stateless_rule_priority
          rule_definition {
            actions = var.stateless_rule_actions
            match_attributes {
              source {
                address_definition = var.stateless_source_address
              }
              destination {
                address_definition = var.stateless_destination_address
              }
              protocols = var.blocked_stateless_protocols
            }
          }
        }
      }
    }
  }
}
resource "aws_networkfirewall_rule_group" "firewall_stateful_dns_block" {
  name     = var.stateful_rule_group_name
  type     = "STATEFUL"
  capacity = var.stateful_rule_group_capacity
  rule_group {
    rules_source {
      rules_string = var.stateful_rules_string
    }
  }
}
# The policy is the only thing the firewall itself points at, and the two default actions on it are what
# decide whether the stateful group is consulted at all.
#
# stateless_default_actions = aws:forward_to_sfe means "no stateless rule matched, hand it to the stateful
# engine". Setting it to aws:pass instead is the quietest way to disable this firewall: every packet is
# allowed, the stateful DNS rules never run, the firewall reports READY, and the only visible difference is
# an empty ALERT log.
resource "aws_networkfirewall_firewall_policy" "firewall_policy" {
  name = var.firewall_policy_name
  firewall_policy {
    stateless_default_actions          = var.stateless_default_actions
    stateless_fragment_default_actions = var.stateless_fragment_default_actions
    # Stateless groups are ordered by an explicit priority; stateful groups are not, which is why only one
    # of these two references carries one.
    stateless_rule_group_reference {
      resource_arn = aws_networkfirewall_rule_group.firewall_stateless_icmp_block.arn
      priority     = var.stateless_rule_group_priority
    }
    stateful_rule_group_reference {
      resource_arn = aws_networkfirewall_rule_group.firewall_stateful_dns_block.arn
    }
  }
}
resource "aws_networkfirewall_firewall" "network_firewall" {
  name                = var.firewall_name
  firewall_policy_arn = aws_networkfirewall_firewall_policy.firewall_policy.arn
  vpc_id              = var.vpc_id

  # One mapping per zone, which is both what AWS requires - each mapping must be in a different zone - and
  # what the route tables need, since each zone's attachment route table points at its own zone's
  # endpoint. These two mappings are also what makes the two zones usable by the firewall at all: an
  # endpoint can only exist in a zone that appears here.
  subnet_mapping {
    subnet_id       = var.firewall_subnet_a_id
    ip_address_type = var.ip_address_type
  }
  subnet_mapping {
    subnet_id       = var.firewall_subnet_b_id
    ip_address_type = var.ip_address_type
  }

  delete_protection                 = var.delete_protection
  subnet_change_protection          = var.subnet_change_protection
  firewall_policy_change_protection = var.firewall_policy_change_protection

  # firewall_policy_arn references the policy, so the graph already orders this after it. The rule groups
  # are a different matter: nothing in this resource mentions them, and a policy that references a rule
  # group ARN is itself ordered after those groups, so the chain holds through the policy. It is left
  # implicit rather than restated because the policy reference is a genuine value dependency, not an
  # ordering hint (rules.md D-1).
}
locals {
  # Maps each firewall subnet to the endpoint AWS instantiated in it.
  #
  # sync_states is a set and its ordering is not meaningful, so the subnet id is the key rather than a
  # position - the same reason the CloudFormation EndpointIds list could not be indexed safely. Both the
  # keys and the values of this map are unknown until apply, which is fine because it is only ever indexed,
  # never used as a for_each (rules.md B-8): the outputs below index it with the two subnet ids the caller
  # passed in, so the output map's own keys stay the literals "a" and "b" and are known at plan.
  #
  # Indexing it with a subnet that is not in sync_states fails at apply with an index error naming that
  # subnet, which is the right failure - it says which zone's endpoint is missing.
  endpoint_id_by_subnet_id = {
    for state in aws_networkfirewall_firewall.network_firewall.firewall_status[0].sync_states :
    state.attachment[0].subnet_id => state.attachment[0].endpoint_id
  }
}
# CloudWatch log groups for the firewall's own logs, one per enabled type.
#
# An addition - the _monolithic template configured no logging - and the reason is in the log_types
# variable: without these, every drop in this project is indistinguishable from a routing mistake.
#
# for_each over a set of configuration literals, so the keys are known at plan (rules.md B-7/B-8), and
# each.value in the name keeps the group that holds the alerts obviously separate from the one that holds
# the flows.
resource "aws_cloudwatch_log_group" "firewall" {
  for_each = var.log_types

  name              = "${var.log_group_name_prefix}/${var.firewall_name}/${lower(each.value)}"
  retention_in_days = var.log_retention_days
  tags = {
    Name = "${var.firewall_name}-${lower(each.value)}"
  }
}
# A separate resource from the firewall, because that is how the API models it, and it is the piece that is
# easiest to leave out: a firewall with no logging configuration is created, reports READY, filters traffic
# correctly and writes nothing anywhere.
#
# count rather than an unconditional resource so that log_types = [] genuinely means "no logging" instead
# of a logging_configuration with an empty destination list, which the API rejects.
resource "aws_networkfirewall_logging_configuration" "network_firewall" {
  count = length(var.log_types) > 0 ? 1 : 0

  firewall_arn = aws_networkfirewall_firewall.network_firewall.arn
  logging_configuration {
    dynamic "log_destination_config" {
      for_each = var.log_types
      content {
        # logGroup, camelCased, because this map is passed through to the API as-is rather than being a
        # Terraform schema. A misspelled key here is accepted by the plan and rejected at apply with
        # InvalidRequestException.
        log_destination = {
          logGroup = aws_cloudwatch_log_group.firewall[log_destination_config.value].name
        }
        log_destination_type = "CloudWatchLogs"
        log_type             = log_destination_config.value
      }
    }
  }
}
