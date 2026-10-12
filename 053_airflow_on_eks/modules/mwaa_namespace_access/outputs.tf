output "namespace" {
  value       = var.namespace
  description = "Namespace the DAG's pods run in, re-exposed so the DAG and the README name the same one (rules.md B-5)"
}
output "user_name" {
  value       = var.user_name
  description = "Kubernetes user the RoleBinding grants the Role to, for the access entry that authenticates the MWAA execution role as that user (rules.md B-5)"
}
output "access_check_command" {
  value       = "for verb in 'create pods' 'get pods/log' 'list events'; do printf '%-14s ' \"$verb\"; kubectl auth can-i $verb --namespace ${var.namespace} --as ${var.user_name}; done"
  description = "Asks the API server directly whether the MWAA execution role's user may do the three things the KubernetesPodOperator needs first. Any \"no\" is the task failing with 403 before it happens"
}
