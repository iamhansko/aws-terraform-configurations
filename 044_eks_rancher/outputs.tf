# Every output is a projection of local.outputs in main.tf, which is also what the
# README written onto the VS Code instance is rendered from (rules.md H-2). No value
# expression is written here: an output that built its own value would be missing
# from that README, and nothing would fail to say so - the apply would succeed
# either way. Whether the pattern still holds is checked by counting: the number of
# output blocks here must equal the number of entries in local.outputs.
#
# description is the one thing repeated, because Terraform rejects an expression
# there ("Variables not allowed") - it has to be a literal.
output "vscode_url" {
  value       = local.outputs.vscode_url.value
  description = "URL to access the code-server web UI on the VS Code EC2 instance"
}
output "cluster_name" {
  value       = local.outputs.cluster_name.value
  description = "Name of the EKS cluster"
}
output "cluster_endpoint" {
  value       = local.outputs.cluster_endpoint.value
  description = "API server endpoint of the EKS cluster"
}
output "rancher_dashboard_url" {
  value       = local.outputs.rancher_dashboard_url.value
  description = "Rancher dashboard URL, served through the pre-created NLB the ingress controller adopts"
}
output "rancher_bootstrap_password_command" {
  value       = local.outputs.rancher_bootstrap_password_command.value
  description = "Command reading Rancher's bootstrap password out of the cluster. A command rather than the value, so an administrator credential is not written into the README that an unauthenticated code-server serves (rules.md H-2)"
}
output "rancher_rollout_command" {
  value       = local.outputs.rancher_rollout_command.value
  description = "Command confirming the Rancher server finished rolling out"
}
output "cert_manager_check_command" {
  value       = local.outputs.cert_manager_check_command.value
  description = "Command listing the cert-manager pods, which Rancher depends on for its ingress certificate"
}
output "ingress_hostname_command" {
  value       = local.outputs.ingress_hostname_command.value
  description = "Command reading the address the ingress controller attached, for comparison against the pre-created load balancer"
}
output "adopted_load_balancer_check_command" {
  value       = local.outputs.adopted_load_balancer_check_command.value
  description = "Command listing every load balancer tagged for this cluster. One is correct; two means adoption failed and the controller built its own (rules.md G-3)"
}
output "update_kubeconfig_command" {
  value       = local.outputs.update_kubeconfig_command.value
  description = "Command that points kubectl on the VS Code instance at the cluster"
}
