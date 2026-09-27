# Every output is a projection of local.outputs in main.tf, which is also what the
# README written onto the VS Code instance is rendered from (rules.md H-2). No value
# expression is written here: an output that built its own value would be missing
# from that README, and nothing would fail to say so - the apply would succeed either
# way. Whether the pattern still holds is checked by counting: the number of output
# blocks here must equal the number of entries in local.outputs.
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
output "vpa_release" {
  value       = local.outputs.vpa_release.value
  description = "The vpa release, its pinned chart version and the namespace it runs in"
}
output "vpa_mode" {
  value       = local.outputs.vpa_mode.value
  description = "The VerticalPodAutoscaler's update mode and the bounds its recommendation must stay inside"
}
output "workload_initial_requests" {
  value       = local.outputs.workload_initial_requests.value
  description = "The CPU and memory requests the demo workload starts with, before any recommendation is applied"
}
output "vpa_components_command" {
  value       = local.outputs.vpa_components_command.value
  description = "Command listing the recommender, updater and admission controller Deployments"
}
output "recommendation_command" {
  value       = local.outputs.recommendation_command.value
  description = "Command showing what the recommender decided for the demo workload"
}
output "applied_requests_command" {
  value       = local.outputs.applied_requests_command.value
  description = "Command showing the requests the running pods actually have, which is where the recommendation lands"
}
output "eviction_events_command" {
  value       = local.outputs.eviction_events_command.value
  description = "Command listing the updater's evictions, the mechanism by which a recommendation is applied"
}
output "vpa_crd_command" {
  value       = local.outputs.vpa_crd_command.value
  description = "Command confirming the VerticalPodAutoscaler CRD the chart installs"
}
output "update_kubeconfig_command" {
  value       = local.outputs.update_kubeconfig_command.value
  description = "Command that points kubectl on the VS Code instance at the cluster"
}
