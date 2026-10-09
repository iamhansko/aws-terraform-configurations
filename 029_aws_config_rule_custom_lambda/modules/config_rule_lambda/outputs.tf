output "rule_name" {
  value       = aws_config_config_rule.config_rule.name
  description = "Name of the Config rule, which every configservice command naming a rule needs"
}
output "rule_arn" {
  value       = aws_config_config_rule.config_rule.arn
  description = "ARN of the rule"
}
output "function_name" {
  value       = aws_lambda_function.lambda_function.function_name
  description = "Name of the function backing the rule"
}
output "function_arn" {
  value       = aws_lambda_function.lambda_function.arn
  description = "ARN of that function, which is also the rule's source_identifier"
}
output "role_arn" {
  value       = aws_iam_role.lambda_role.arn
  description = "ARN of the function's execution role"
}
output "role_name" {
  value       = aws_iam_role.lambda_role.name
  description = "Generated name of that role, so what is attached to it can be listed without finding it in the console first"
}
output "log_group_name" {
  value       = var.log_group_name
  description = "Log group the function writes to, re-exposed so the caller builds its log command from the same value the function was configured with rather than restating it (rules.md B-5)"
}
output "remediation_enabled" {
  value       = length(var.remediation_policy_actions) > 0
  description = "Whether the handler was granted the IAM writes it needs to fix what it finds, re-exposed so the caller's outputs can describe the right demo (rules.md B-5). True means a non-compliant fixture becomes compliant moments after it is first evaluated"
}
output "compliance_details_command" {
  # Built here, where the rule's name is (rules.md B-5).
  value       = "aws configservice get-compliance-details-by-config-rule --region ${var.region} --config-rule-name ${aws_config_config_rule.config_rule.name} --query 'EvaluationResults[].[EvaluationResultIdentifier.EvaluationResultQualifier.ResourceId,ComplianceType,Annotation]' --output table"
  description = "The rule's verdicts, one row per evaluated instance. An empty table straight after apply is the expected state, not a failure: this is a change-triggered rule, so it has nothing to say until an instance carrying one of the governed profiles is recorded"
}
output "force_evaluation_command" {
  value       = "aws configservice start-config-rules-evaluation --region ${var.region} --config-rule-names ${aws_config_config_rule.config_rule.name}"
  description = "Re-runs the rule against the configuration items already recorded, instead of waiting for the next change. Returns immediately and evaluates asynchronously, so give it a minute before reading the compliance details again"
}
output "log_command" {
  value       = "aws logs tail ${var.log_group_name} --region ${var.region} --since 30m --follow"
  description = "The handler's log. This is the only place a rule that never evaluates explains itself: Runtime.HandlerNotFound, an AccessDenied from a missing policy and a timeout all leave the rule sitting at \"No results available\" with nothing in the Config console to distinguish them. A log group that does not exist at all means the function has never been invoked, which points at the recorder rather than at the rule"
}
