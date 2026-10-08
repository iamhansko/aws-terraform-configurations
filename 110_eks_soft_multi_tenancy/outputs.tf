# Every value here is a projection of local.outputs in main.tf, which the README written onto the workbench
# renders from the same map - so no value expression exists twice, and an output cannot be added without also
# appearing in that README (rules.md B-5/H-2).
#
# description is the one thing that cannot be projected: Terraform rejects an expression in an output's
# description ("Variables not allowed"), so the wording is a literal on both sides.
output "vscode_url" {
  value       = local.outputs.vscode_url.value
  description = "Open the IDE here. kubectl is pointed at the cluster as an admin"
}
output "management_ui_url" {
  value       = local.outputs.management_ui_url.value
  description = "The Calico stars graph, through the pre-created NLB the controller adopted"
}
output "what_to_look_for" {
  value       = local.outputs.what_to_look_for.value
  description = "Whether the policies are applied and whether the CNI enforces them - the two settings that decide what the graph shows"
}
output "cni_enforcement_command" {
  value       = local.outputs.cni_enforcement_command.value
  description = "1. Whether the VPC CNI enforces NetworkPolicy at all. The original left this off"
}
output "policy_list_command" {
  value       = local.outputs.policy_list_command.value
  description = "2. Which policies the API server holds, which says nothing about enforcement"
}
output "cross_tenant_test_command" {
  value       = local.outputs.cross_tenant_test_command.value
  description = "3. Probes one tenant's frontend against every tenant's backend"
}
output "quota_command" {
  value       = local.outputs.quota_command.value
  description = "4. The quotas and limit ranges, which are the half of multi-tenancy IAM does nothing about"
}
output "assume_tenant_command" {
  value       = local.outputs.assume_tenant_command.value
  description = "5. Assumes a tenant role, after which kubectl sees only that tenant's namespace"
}
output "tenant_scope_command" {
  value       = local.outputs.tenant_scope_command.value
  description = "6. What each tenant is allowed, read from the cluster"
}
output "adopted_load_balancer_check_command" {
  value       = local.outputs.adopted_load_balancer_check_command.value
  description = "7. Lists every load balancer tagged for this cluster. One is correct; two means adoption failed silently"
}
output "service_address_command" {
  value       = local.outputs.service_address_command.value
  description = "8. The address the controller actually attached, for comparing against the pre-created one"
}
output "tenant_roles" {
  value       = local.outputs.tenant_roles.value
  description = "The tenant roles and the namespace each is scoped to"
}
output "update_kubeconfig_command" {
  value       = local.outputs.update_kubeconfig_command.value
  description = "Re-points kubectl at the cluster. User data already ran this"
}
output "private_key_command" {
  value       = local.outputs.private_key_command.value
  description = "Reads the workbench's SSH private key out of SSM Parameter Store"
}
