output "operator_namespace" {
  value       = var.operator_namespace
  description = "Namespace the OpenTelemetry Operator and the collector run in, re-exposed so the add-on module and the caller's diagnostic commands read one value (rules.md B-5)"
}
output "cluster_role_name" {
  value       = var.cluster_role_name
  description = "Name of the cluster-scoped Role granted to the add-on manager"
}
output "addon_manager_user" {
  value       = var.addon_manager_user
  description = "Kubernetes user EKS installs the add-on as, re-exposed because a forbidden error from the add-on names this exact user and the fix is always one of these bindings (rules.md B-5)"
}
output "permission_check_command" {
  value       = "kubectl get clusterrole ${var.cluster_role_name} && kubectl -n ${var.operator_namespace} get role,rolebinding"
  description = "Whether the grant is in place. Worth checking first when the ADOT add-on reports a create failure: the message names the object it could not create, and every one of them is covered by a rule here"
}
output "can_i_command" {
  value       = "kubectl auth can-i create customresourcedefinitions --as ${var.addon_manager_user}"
  description = "Asks the API server the same question the add-on manager does, as the user it acts as. The answer is the whole point of this module, and it is a faster check than reading the rules"
}
