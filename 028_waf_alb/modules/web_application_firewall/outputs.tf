output "web_acl_arn" {
  value       = aws_wafv2_web_acl.web_acl.arn
  description = "ARN of the web ACL, which is what every wafv2 CLI call identifies it by"
}
output "web_acl_id" {
  value       = aws_wafv2_web_acl.web_acl.id
  description = "ID of the web ACL. Needed together with the name and the scope to address it through update-web-acl, which is the one API that takes all three"
}
output "web_acl_name" {
  value       = aws_wafv2_web_acl.web_acl.name
  description = "Name of the web ACL, which is also the WebACL dimension on its CloudWatch metrics"
}
output "web_acl_capacity" {
  value       = aws_wafv2_web_acl.web_acl.capacity
  description = "Web ACL capacity units the configured rules consume, computed by WAF rather than by Terraform. A web ACL is capped at 1500 WCU by default and the two managed groups here take a visible share of it, so this is the number that decides how many more groups will fit"
}
output "scope" {
  value       = var.scope
  description = "Scope the web ACL was created with, handed straight back out so the caller's verification commands do not restate REGIONAL (rules.md B-5). GetSampledRequests requires it and rejects a mismatch"
}
output "default_action" {
  value       = var.default_action
  description = "What happens to a request no rule matched. Re-exposed because it is the single value that decides whether the demo's plain request returns 200 at all"
}
output "associated_resource_arns" {
  value       = var.associated_resource_arns
  description = "What this web ACL was associated with, keyed by the caller's label and handed back so a plan or an output shows the association rather than only the ACL (rules.md B-5). An empty map is a web ACL that filters nothing, which no attribute of the ACL itself reveals"
}
output "managed_rule_group_summary" {
  value       = local.managed_rule_group_summary
  description = "The configured rule groups in evaluation order, with their override actions and metric names. This is the content of the demo in one block, and it is the thing to read next to a 403 to work out which group should have produced it"
}
output "sampled_requests_command" {
  value       = local.sampled_requests_commands
  description = "One command per rule group plus one for the default action, reading back the requests WAF sampled. This is how a 403 is attributed: a blocked probe appears under the rule group's metric name with the matching rule named in the sample. A 403 that appears nowhere here did not come from WAF - look at the target and the listener instead"
}
output "blocked_request_metrics_command" {
  value       = local.blocked_request_metrics_commands
  description = "BlockedRequests from CloudWatch. Run the list-metrics line first: it prints the dimension sets that actually exist, and the get-metric-statistics line that follows assumes WebACL and Rule"
}
output "web_acl_for_resource_command" {
  value       = local.web_acl_for_resource_commands
  description = "Asks each associated resource which web ACL is in front of it. The opposite direction from this module's state, and therefore the one that can disagree with it - an empty answer here with an association in state means something removed it outside Terraform"
}
output "describe_managed_rule_group_commands" {
  value = join("\n", [
    for name in local.rule_group_names_by_priority :
    "aws wafv2 describe-managed-rule-group --vendor-name ${var.managed_rule_groups[name].vendor_name} --name ${name} --scope ${var.scope}"
  ])
  description = "Lists the individual rules inside each managed group, with their default actions and labels. These are the names rule_action_overrides takes, and the only way to get them right - an override naming a rule the group does not contain is rejected during apply with nothing in the plan to warn about it"
}
