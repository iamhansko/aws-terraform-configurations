# Every output is a projection of local.outputs in main.tf, which is also what the README written
# onto the VS Code instance is rendered from (rules.md H-2). No value expression is written here: an
# output that built its own value would be missing from that README, and nothing would fail to say
# so - the apply would succeed either way. Whether the pattern still holds is checked by counting:
# the number of output blocks here must equal the number of entries in local.outputs.
#
# Neither the Keycloak admin password nor the database password is exposed. The _monolithic template
# published the admin credentials as a single plaintext output, which also wrote them into the
# instance README that an unauthenticated code-server serves (rules.md H-2).
#
# description is the one thing repeated, because Terraform rejects an expression there ("Variables
# not allowed") - it has to be a literal.
output "vscode_url" {
  value       = local.outputs.vscode_url.value
  description = "URL to access the code-server web UI on the VS Code EC2 instance"
}
output "cluster_name" {
  value       = local.outputs.cluster_name.value
  description = "Name of the EKS cluster"
}
output "keycloak_url" {
  value       = local.outputs.keycloak_url.value
  description = "Keycloak console URL, served over https through the pre-created ALB the controller adopts (rules.md G-3)"
}
output "keycloak_admin_username" {
  value       = local.outputs.keycloak_admin_username.value
  description = "Login name for the Keycloak bootstrap admin. The password is not exposed as an output (rules.md H-2)"
}
output "certificate_status" {
  value       = local.outputs.certificate_status.value
  description = "The certificate's domain and status. ISSUED means ACM saw the validation records this project created"
}
output "keycloak_rollout_command" {
  value       = local.outputs.keycloak_rollout_command.value
  description = "Command confirming the Keycloak StatefulSet finished starting"
}
output "keycloak_pods_command" {
  value       = local.outputs.keycloak_pods_command.value
  description = "Command listing the Keycloak and PostgreSQL pods"
}
output "keycloak_ingress_command" {
  value       = local.outputs.keycloak_ingress_command.value
  description = "Command showing whether the controller gave Keycloak's Ingress an address"
}
output "adopted_load_balancer_check_command" {
  value       = local.outputs.adopted_load_balancer_check_command.value
  description = "Command listing every load balancer tagged for this cluster. One is correct; two means adoption failed and the controller built its own (rules.md G-3)"
}
output "certificate_status_command" {
  value       = local.outputs.certificate_status_command.value
  description = "Command showing the ACM certificate's status and each name's validation state"
}
output "keycloak_logs_command" {
  value       = local.outputs.keycloak_logs_command.value
  description = "Command reading Keycloak's log, where a database or proxy-header problem explains itself"
}
output "update_kubeconfig_command" {
  value       = local.outputs.update_kubeconfig_command.value
  description = "Command that points kubectl on the VS Code instance at the cluster"
}
