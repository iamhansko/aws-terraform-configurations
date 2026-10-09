output "firewall_arn" {
  value       = aws_networkfirewall_firewall.network_firewall.arn
  description = "ARN of the firewall"
}
output "firewall_name" {
  value       = aws_networkfirewall_firewall.network_firewall.name
  description = "Name of the firewall, for the describe-firewall calls in the root's outputs"
}
output "firewall_policy_arn" {
  value       = aws_networkfirewall_firewall_policy.firewall_policy.arn
  description = "ARN of the policy the firewall uses"
}
output "rule_group_arns" {
  value = {
    stateless_icmp_block = aws_networkfirewall_rule_group.stateless_icmp_block.arn
    stateful_dns_block   = aws_networkfirewall_rule_group.stateful_dns_block.arn
  }
  description = "ARNs of the two rule groups. Both are attached to the policy and neither is reachable by any packet, for the reason set out above aws_networkfirewall_firewall in main.tf"
}
output "stateful_rules_string" {
  value       = local.stateful_rules_string
  description = "The rendered Suricata rules. Worth being able to read without applying anything: these are generated from the protocol list and the sid base, and a duplicate sid is rejected when the rule group is created rather than at plan"
}
# The endpoint ids, which are the values the inspection routes described in main.tf would need.
#
# Destructured rather than left as the raw status object because the shape is awkward:
# firewall_status is a single-element list, sync_states inside it is a set rather than a map, and
# each state's attachment is itself a nested collection. Iterating with for works over all of them.
#
# Every value here is unknown until apply, so this map must not become a for_each - the keys are
# availability zone names read back from the firewall, not configuration (rules.md B-8). A route
# using one would be written as for_each over the zone suffixes with a lookup into this map, which
# keeps the keys in configuration and lets the values stay unknown.
output "endpoint_ids_by_zone" {
  value = {
    for state in aws_networkfirewall_firewall.network_firewall.firewall_status[0].sync_states :
    state.availability_zone => [for attachment in state.attachment : attachment.endpoint_id][0]
  }
  description = "The firewall's VPC endpoint IDs by availability zone name. Nothing in this project routes to them - they are here so the three route changes documented in main.tf can be written without first querying the firewall"
}
output "endpoint_subnets_by_zone" {
  value = {
    for state in aws_networkfirewall_firewall.network_firewall.firewall_status[0].sync_states :
    state.availability_zone => [for attachment in state.attachment : attachment.subnet_id][0]
  }
  description = "Which subnet each endpoint landed in, by zone. Pairing this against the egress VPC's firewall subnets confirms the endpoints are where they were asked to be"
}
output "describe_command" {
  value       = "aws network-firewall describe-firewall --firewall-name ${aws_networkfirewall_firewall.network_firewall.name} --query '{Status:FirewallStatus.Status,Sync:FirewallStatus.SyncStates,Subnets:Firewall.SubnetMappings,DeleteProtection:Firewall.DeleteProtection}' --output json"
  description = "The firewall's own view of itself. Status READY with an endpoint per zone is the expected result, and it is also the result when no traffic is reaching it - this command confirms the firewall exists and says nothing about whether it is in the data path"
}
output "flow_log_group_name" {
  value       = var.enable_logging ? aws_cloudwatch_log_group.firewall["FLOW"].name : null
  description = "CloudWatch log group receiving FLOW logs, or null when logging is off. This is the one place that answers whether the firewall sees traffic: with the routing this project reproduces it stays empty, so an empty group minutes after the probes have run is the positive confirmation that the endpoints are bypassed"
}
output "alert_log_group_name" {
  value       = var.enable_logging ? aws_cloudwatch_log_group.firewall["ALERT"].name : null
  description = "CloudWatch log group receiving ALERT logs, or null when logging is off. A drop by either rule group would be logged here"
}
output "flow_log_command" {
  value       = var.enable_logging ? "aws logs tail ${aws_cloudwatch_log_group.firewall["FLOW"].name} --since 15m --format short" : "logging is disabled; set enable_firewall_logging = true to observe whether the firewall receives traffic"
  description = "Tails the FLOW log. Run it after the egress probes. No output means no packet reached the firewall, which with these route tables is the expected and documented outcome rather than a transient condition"
}
