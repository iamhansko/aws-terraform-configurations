output "firewall_arn" {
  value       = aws_networkfirewall_firewall.network_firewall.arn
  description = "ARN of the firewall. Note that this resource's id attribute is also the ARN, which is why the _monolithic template could pass .id where an ARN was wanted and still work - naming .arn says what is meant"
}
output "firewall_name" {
  value       = aws_networkfirewall_firewall.network_firewall.name
  description = "Name of the firewall, which is the handle every describe-firewall call takes"
}
output "firewall_policy_arn" {
  value       = aws_networkfirewall_firewall_policy.firewall_policy.arn
  description = "ARN of the firewall policy, for attaching the same policy to a second firewall - the relationship is many firewalls to one policy"
}
output "firewall_endpoint_a_id" {
  value       = local.endpoint_id_by_subnet_id[var.firewall_subnet_a_id]
  description = "vpce-... id of the firewall endpoint in the first zone's subnet, which is what the first zone's transit gateway attachment route table must name as its 0.0.0.0/0 target. Resolved from the subnet that was passed in rather than by position, so it cannot silently become the other zone's endpoint"
}
output "firewall_endpoint_b_id" {
  value       = local.endpoint_id_by_subnet_id[var.firewall_subnet_b_id]
  description = "vpce-... id of the firewall endpoint in the second zone's subnet"
}
output "firewall_endpoint_ids" {
  value = {
    (var.firewall_subnet_a_id) = local.endpoint_id_by_subnet_id[var.firewall_subnet_a_id]
    (var.firewall_subnet_b_id) = local.endpoint_id_by_subnet_id[var.firewall_subnet_b_id]
  }
  description = "Both endpoint ids keyed by the subnet they live in. For reading in terraform output and comparing against what the route tables actually point at - the one mistake in this area that produces no error is a route naming the other zone's endpoint"
}
output "firewall_status_command" {
  value       = "aws network-firewall describe-firewall --firewall-name ${aws_networkfirewall_firewall.network_firewall.name} --query 'FirewallStatus.[Status,ConfigurationSyncStateSummary]' --output text"
  description = "Whether the firewall is READY and whether its configuration has finished syncing. Terraform returns from apply once the firewall resource exists, which is before the endpoints are serving - a drop test run too early passes for the wrong reason"
}
output "firewall_endpoints_command" {
  value       = "aws network-firewall describe-firewall --firewall-name ${aws_networkfirewall_firewall.network_firewall.name} --query 'FirewallStatus.SyncStates.*.Attachment.[EndpointId,SubnetId,Status]' --output text"
  description = "One line per zone: the endpoint id, the subnet it is in and whether it is READY. Two READY lines is the healthy result; one means a zone's traffic is being routed at an endpoint that is not serving yet, which drops silently"
}
output "log_group_names" {
  value       = { for log_type, group in aws_cloudwatch_log_group.firewall : log_type => group.name }
  description = "CloudWatch log group per enabled log type. Empty when log_types is empty, which is the _monolithic template's behaviour and the state in which this project can demonstrate nothing"
}
output "alert_log_command" {
  value       = contains(tolist(var.log_types), "ALERT") ? "aws logs tail ${var.log_group_name_prefix}/${var.firewall_name}/alert --since 15m --format short" : "ALERT logging is disabled - set log_types to include ALERT"
  description = <<-DESC
    Tails what the firewall dropped. This is the direct evidence the rules fired: a ping from the spoke
    instance should appear as a stateless drop, and a dig at a public resolver as a stateful one.

    An empty tail while traffic is definitely being blocked means the traffic is not reaching the firewall
    at all - look at the attachment route tables next, not at the rules.
  DESC
}
output "flow_log_command" {
  value       = contains(tolist(var.log_types), "FLOW") ? "aws logs tail ${var.log_group_name_prefix}/${var.firewall_name}/flow --since 15m --format short" : "FLOW logging is disabled - set log_types to include FLOW"
  description = "Tails every connection the firewall handled, dropped or not. This is the half that proves the traffic which succeeded went through the firewall rather than around it - a curl that returns a NAT gateway address but leaves no flow record means a route is sending traffic straight to the NAT gateway"
}
