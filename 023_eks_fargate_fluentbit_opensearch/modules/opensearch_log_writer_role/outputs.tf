output "role_name" {
  value       = opensearch_role.log_writer.role_name
  description = "Name of the OpenSearch security role created for the log shipper"
}
output "backend_role_arns" {
  value       = var.backend_role_arns
  description = "The IAM role ARNs mapped onto the role, re-exposed so a mismatch with the identity Fluent Bit actually signs as is visible in outputs rather than only in a 403 (rules.md B-5)"
}
output "roles_mapping_check_command" {
  value       = "curl -s -u \"$OPENSEARCH_USER:$OPENSEARCH_PASSWORD\" https://$OPENSEARCH_ENDPOINT/_plugins/_security/api/rolesmapping/${opensearch_role.log_writer.role_name}"
  description = "Command showing the mapping as the domain holds it, which is the only place the IAM-to-OpenSearch link is observable. Reads the credential and endpoint from the environment rather than embedding them in a command that lands in shell history (rules.md H-2)"
}
