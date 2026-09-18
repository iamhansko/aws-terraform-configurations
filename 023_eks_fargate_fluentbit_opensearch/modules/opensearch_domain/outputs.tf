output "domain_name" {
  value       = aws_opensearch_domain.opensearch.domain_name
  description = "Name of the OpenSearch domain, read from the resource rather than echoing the variable (rules.md B-5)"
}
output "endpoint" {
  value       = aws_opensearch_domain.opensearch.endpoint
  description = "Host part of the domain's HTTPS endpoint, with no scheme. This is what Fluent Bit's Host field takes"
}
output "arn" {
  value       = aws_opensearch_domain.opensearch.arn
  description = "ARN of the domain. Used to scope the pod execution role's es:* permission to this one domain"
}
output "dashboard_url" {
  value       = "https://${aws_opensearch_domain.opensearch.endpoint}/_dashboards"
  description = "OpenSearch Dashboards URL. Log in with the master user - it is not IAM-authenticated"
}
output "kms_key_arn" {
  value       = aws_kms_key.opensearch.arn
  description = "ARN of the KMS key encrypting the domain at rest"
}
output "index_check_command" {
  value       = "curl -s -u \"$OPENSEARCH_USER:$OPENSEARCH_PASSWORD\" https://${aws_opensearch_domain.opensearch.endpoint}/_cat/indices?v"
  description = "Command listing the indices the domain holds, which is how to tell whether Fluent Bit has written anything. Expects OPENSEARCH_USER and OPENSEARCH_PASSWORD in the environment rather than embedding the password in a command that ends up in shell history (rules.md H-2)"
}
