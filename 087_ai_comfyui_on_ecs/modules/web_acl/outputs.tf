output "arn" {
  value       = aws_wafv2_web_acl.acl.arn
  description = "ARN of the web ACL"
}
output "name" {
  value       = aws_wafv2_web_acl.acl.name
  description = "Name of the web ACL"
}
output "default_action" {
  value       = local.restricted ? "block" : "allow"
  description = "What the ACL does with a request no rule matched: block when an allow-list is configured, allow otherwise (rules.md B-5)"
}
output "sampled_requests_command" {
  value       = "aws wafv2 get-sampled-requests --scope REGIONAL --web-acl-arn ${aws_wafv2_web_acl.acl.arn} --rule-metric-name WebACL --max-items 100 --time-window StartTime=$(date -u -d '-3 hours' +%Y-%m-%dT%H:%M:%SZ),EndTime=$(date -u +%Y-%m-%dT%H:%M:%SZ) --query 'SampledRequests[].[Action,Request.ClientIP,Request.URI]' --output table"
  description = "Requests the ACL saw in the last three hours and what it did with them - where an address that cannot reach the load balancer finds out why"
}
