# Every value here is a projection of local.outputs in main.tf. No output in this file carries a value
# expression of its own.
#
# That is what rules.md H-2 requires of a root that declares module "vscode_ec2": the work happens inside
# code-server in a browser, where terraform output does not exist, so the same values are written into a
# README on the instance - and the only way to stop the two copies drifting is for both to read one map. An
# output declared here with its own expression would be missing from that README and nothing would report
# it, because the apply succeeds either way.
#
# The count is the check: this file has twenty-one output blocks and local.outputs has twenty-one entries.
#
# The _monolithic template had two outputs, VsCode and KeyPairValue. Both are still here - vscode_url and
# key_pair_parameter_console_url - and they are in the map like everything else. The other nineteen exist
# because this project's interesting facts are all about a running system: whether the target is in service,
# whether a request was refused, and which rule refused it. None of those is a resource attribute, so they
# are published as commands.
#
# Descriptions are the one thing restated on both sides, because Terraform does not allow an expression in
# an output description - "Error: Variables not allowed" - so they are literals here and in the map while
# the values exist only in the map.
output "vscode_url" {
  value       = local.outputs.vscode_url.value
  description = "The code-server IDE on the workbench, and the _monolithic template's VsCode output. No password - it runs with auth: none, so the address and vscode_ingress_cidr_blocks are the only protection"
}
output "alb_url" {
  value       = local.outputs.alb_url.value
  description = "The load balancer the web ACL is associated with. Every request in this demo goes here"
}
output "target_health_command" {
  value       = local.outputs.target_health_command.value
  description = "1. State of the registered target. Unhealthy for the first two and a half minutes after apply is the default health check settings, not a fault"
}
output "waf_check_command" {
  value       = local.outputs.waf_check_command.value
  description = "2. The whole demo in one paste: an ordinary request, a SQL injection and a path traversal through the same endpoint. 200, 403, 403 is the web ACL working"
}
output "allowed_request_command" {
  value       = local.outputs.allowed_request_command.value
  description = "The benign request on its own - the control that proves the endpoint serves at all"
}
output "sqli_request_command" {
  value       = local.outputs.sqli_request_command.value
  description = "The SQL injection on its own. 403 from AWSManagedRulesSQLiRuleSet; 200 with the table in the body means it reached the application"
}
output "path_traversal_request_command" {
  value       = local.outputs.path_traversal_request_command.value
  description = "The path traversal on its own. 403 from AWSManagedRulesCommonRuleSet, which is what distinguishes the two rule groups"
}
output "sampled_requests_command" {
  value       = local.outputs.sampled_requests_command.value
  description = "3. Reads the blocked requests back out of WAF, one command per rule group plus the default action. A 403 that appears nowhere here did not come from WAF"
}
output "blocked_request_metrics_command" {
  value       = local.outputs.blocked_request_metrics_command.value
  description = "4. BlockedRequests from CloudWatch. Run the list-metrics line first - it prints the dimension sets that actually exist"
}
output "web_acl_for_resource_command" {
  value       = local.outputs.web_acl_for_resource_command.value
  description = "Asks the load balancer which web ACL is in front of it. Essential before trusting a 200: an unassociated web ACL filters nothing and says nothing"
}
output "managed_rule_group_summary" {
  value       = local.outputs.managed_rule_group_summary.value
  description = "The configured rule groups in evaluation order, with their override actions and metric names"
}
output "describe_managed_rule_group_commands" {
  value       = local.outputs.describe_managed_rule_group_commands.value
  description = "Lists the individual rules inside each managed group. These are the names rule_action_overrides takes"
}
output "web_acl_arn" {
  value       = local.outputs.web_acl_arn.value
  description = "ARN of the web ACL, which is what every wafv2 call identifies it by"
}
output "web_acl_capacity" {
  value       = local.outputs.web_acl_capacity.value
  description = "Capacity units the configured rule groups consume against the web ACL's 1500 unit default limit, as computed by WAF"
}
output "app_server_direct_request_command" {
  value       = local.outputs.app_server_direct_request_command.value
  description = "The same injection sent straight at the instance, around the load balancer and so around the web ACL. Times out with app_server_ingress_cidr_blocks empty, which is the default and the point"
}
output "app_server_session_command" {
  value       = local.outputs.app_server_session_command.value
  description = "Session Manager onto the app server, which is the only way in - there is no SSH ingress rule on that host"
}
output "app_server_service_command" {
  value       = local.outputs.app_server_service_command.value
  description = "Whether the Flask unit is running on the app server, and its recent journal"
}
output "app_server_cloud_init_log_command" {
  value       = local.outputs.app_server_cloud_init_log_command.value
  description = "The app server's bootstrap log. Connection timeouts here mean egress or the missing public address"
}
output "vscode_cloud_init_log_command" {
  value       = local.outputs.vscode_cloud_init_log_command.value
  description = "The workbench's bootstrap log. First place to look when the IDE does not answer"
}
output "private_key_command" {
  value       = local.outputs.private_key_command.value
  description = "Retrieves the generated SSH private key from Parameter Store. A command rather than the key, so this does not print a secret"
}
output "key_pair_parameter_console_url" {
  value       = local.outputs.key_pair_parameter_console_url.value
  description = "The same key pair parameter in the console, which is the _monolithic template's KeyPairValue output"
}
