# Every value here is a projection of local.outputs in main.tf, which the README written onto the
# VS Code instance renders from the same map - so no value expression exists twice, and an output
# cannot be added without also appearing in that README (rules.md B-5/H-2).
#
# The Postgres passwords are the deliberate omission: they are in neither the map nor here, and the
# README carries the command to read them out of the cluster instead (rules.md H-2).
#
# description is the one thing that cannot be projected: Terraform rejects an expression in an
# output's description ("Variables not allowed"), so the wording is a literal on both sides.
output "vscode_url" {
  value       = local.outputs.vscode_url.value
  description = "Open the IDE here. The kubectl commands below are meant to be run from its terminal"
}
output "n8n_url" {
  value       = local.outputs.n8n_url.value
  description = "The n8n editor. First visit claims the owner account, so treat this address as unauthenticated until you have"
}
output "cluster_name" {
  value       = local.outputs.cluster_name.value
  description = "Name of the EKS cluster"
}
output "cluster_endpoint" {
  value       = local.outputs.cluster_endpoint.value
  description = "API server endpoint. Public so the helm and kubectl providers could reach it during apply"
}
output "n8n_deployment" {
  value       = local.outputs.n8n_deployment.value
  description = "The n8n image deployed and the external URL it was told about, which is what makes its webhook URLs reachable"
}
output "postgres_rollout_command" {
  value       = local.outputs.postgres_rollout_command.value
  description = "1. Waits for Postgres, which has to finish initialising before n8n stops restarting"
}
output "n8n_rollout_command" {
  value       = local.outputs.n8n_rollout_command.value
  description = "2. Waits for n8n"
}
output "pods_command" {
  value       = local.outputs.pods_command.value
  description = "3. Both pods and both claims, which is where a storage problem shows up"
}
output "adopted_load_balancer_check_command" {
  value       = local.outputs.adopted_load_balancer_check_command.value
  description = "4. Lists every load balancer tagged for this cluster. One is correct; two means adoption failed silently"
}
output "ingress_address_command" {
  value       = local.outputs.ingress_address_command.value
  description = "5. The address the controller assigned to the Ingress. An empty ADDRESS means nothing is reconciling it, which is a missing ingressClassName rather than a load balancer problem"
}
output "ingress_events_command" {
  value       = local.outputs.ingress_events_command.value
  description = "6. What the controller did with the Ingress, which is where subnet discovery and target group problems are reported"
}
output "http_check_command" {
  value       = local.outputs.http_check_command.value
  description = "7. Fetches the editor over http and prints the status code - the one check that exercises listener, target group, security group rule and n8n together"
}
output "db_init_command" {
  value       = local.outputs.db_init_command.value
  description = "8. The Job that reconciles Postgres's application role with this configuration, and its log. The apply waits for it to complete, so a failure here fails the apply"
}
output "logs_command" {
  value       = local.outputs.logs_command.value
  description = "6. n8n's log, where a database authentication failure points at Postgres's first-start script"
}
output "credentials_command" {
  value       = local.outputs.credentials_command.value
  description = "7. Reads the generated Postgres credentials out of the cluster. They are not exposed as Terraform outputs on purpose"
}
output "update_kubeconfig_command" {
  value       = local.outputs.update_kubeconfig_command.value
  description = "Re-points kubectl at the cluster. User data already ran this"
}
