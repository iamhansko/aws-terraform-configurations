# Every value here is a projection of local.outputs in main.tf, which the README written onto the workbench
# renders from the same map - so no value expression exists twice, and an output cannot be added without also
# appearing in that README (rules.md B-5/H-2).
#
# description is the one thing that cannot be projected: Terraform rejects an expression in an output's
# description ("Variables not allowed"), so the wording is a literal on both sides.
#
# Nothing here is sensitive, and that is deliberate rather than lucky. The two secrets this project holds -
# the Karmada cluster-admin kubeconfig and the workbench's SSH key - are both in Parameter Store as
# SecureStrings, and what appears below is the command to fetch each one. The alternative would be outputs
# marked sensitive, which Terraform would then also have to be kept out of the workbench's README by hand.
output "vscode_url" {
  value       = local.outputs.vscode_url.value
  description = "Open the IDE here. Its KUBECONFIG already names the three EKS clusters and the Karmada API server"
}
output "what_terraform_manages" {
  value       = local.outputs.what_terraform_manages.value
  description = "The clusters, the Karmada release and the workbench this root owns. All of it, unlike the previous version of this project, which left three EKS clusters running after a destroy"
}
output "karmada_api_endpoint" {
  value       = local.outputs.karmada_api_endpoint.value
  description = "Address of the Karmada API server. The certificate, both member agents and the Terraform provider that created the demo workload are all built around this one value"
}
output "karmada_credentials_command" {
  value       = local.outputs.karmada_credentials_command.value
  description = "1. Lists the Karmada client credentials in Parameter Store. Already assembled into a kubeconfig on the workbench; this is for using them elsewhere"
}
output "member_clusters_command" {
  value       = local.outputs.member_clusters_command.value
  description = "2. The clusters Karmada manages and whether each is Ready. The check that the deployment worked"
}
output "propagation_policy_command" {
  value       = local.outputs.propagation_policy_command.value
  description = "3. The policy that decides which member clusters the demo workload lands on"
}
output "aggregate_workload_command" {
  value       = local.outputs.aggregate_workload_command.value
  description = "4. The demo Deployment as the Karmada API server sees it, with replica counts collected from the members"
}
output "scheduling_decision_command" {
  value       = local.outputs.scheduling_decision_command.value
  description = "5. The scheduler's actual decision: which member cluster got how many replicas"
}
output "member_workload_command" {
  value       = local.outputs.member_workload_command.value
  description = "6. The pods inside a member cluster, which is where the workload actually runs"
}
output "karmada_control_plane_command" {
  value       = local.outputs.karmada_control_plane_command.value
  description = "7. Karmada's own components on the parent cluster"
}
output "agent_logs_command" {
  value       = local.outputs.agent_logs_command.value
  description = "8. A member agent's log, which is where a registration that never appears explains itself"
}
output "load_balancer_health_command" {
  value       = local.outputs.load_balancer_health_command.value
  description = "9. Target health on the load balancer in front of the Karmada API server"
}
output "certificate_command" {
  value       = local.outputs.certificate_command.value
  description = "10. The Karmada certificate's subject and SANs, read back out of the cluster"
}
output "workbench_security_groups_command" {
  value       = local.outputs.workbench_security_groups_command.value
  description = "11. The security groups on the workbench. Four expected: its own, plus each cluster's primary group"
}
output "private_key_command" {
  value       = local.outputs.private_key_command.value
  description = "Reads the workbench's SSH private key out of SSM Parameter Store"
}
