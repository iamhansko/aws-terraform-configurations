# Every value here is a projection of local.outputs in main.tf, which the README written onto
# the VS Code instance renders from the same map - so no value expression exists twice, and an
# output cannot be added without also appearing in that README (rules.md B-5/H-2).
#
# description is the one thing that cannot be projected: Terraform rejects an expression in an
# output's description ("Variables not allowed"), so the wording is a literal on both sides.
output "vscode_url" {
  value       = local.outputs.vscode_url.value
  description = "Open the IDE here. The kubectl commands below are meant to be run from its terminal"
}
output "kube_ops_view_url" {
  value       = local.outputs.kube_ops_view_url.value
  description = "The dashboard that makes the scaling visible: every box a node, every square inside it a pod"
}
output "cluster_name" {
  value       = local.outputs.cluster_name.value
  description = "Name of the EKS cluster, which is also what the autoscaler's Auto Scaling group auto-discovery matches on"
}
output "cluster_endpoint" {
  value       = local.outputs.cluster_endpoint.value
  description = "API server endpoint. Public so the helm and kubectl providers could reach it during apply"
}
output "node_group_bounds" {
  value       = local.outputs.node_group_bounds.value
  description = "The floor and ceiling the autoscaler works between, the instance type, and the zones the node group spans"
}
output "workload_demand" {
  value       = local.outputs.workload_demand.value
  description = "The demo Deployments, their total CPU request and the topology each spreads across"
}
output "scale_down_wait" {
  value       = local.outputs.scale_down_wait.value
  description = "How long a node must sit underutilized before the autoscaler removes it"
}
output "autoscaler_status_command" {
  value       = local.outputs.autoscaler_status_command.value
  description = "1. The autoscaler's status ConfigMap, which is the only place that says whether auto-discovery matched the node group at all"
}
output "pending_pods_command" {
  value       = local.outputs.pending_pods_command.value
  description = "2. The pods with nowhere to go, which is the autoscaler's only input"
}
output "node_watch_command" {
  value       = local.outputs.node_watch_command.value
  description = "3. Watches nodes arrive and leave, with their availability zone and instance type"
}
output "pod_distribution_command" {
  value       = local.outputs.pod_distribution_command.value
  description = "4. Counts each Deployment's pods per node, which is how the zone spread and the hostname spread are told apart"
}
output "autoscaler_logs_command" {
  value       = local.outputs.autoscaler_logs_command.value
  description = "5. The autoscaler's reasoning, where a scale-up that never happened is explained"
}
output "scale_in_command" {
  value       = local.outputs.scale_in_command.value
  description = "6. Takes the demo Deployments to zero replicas to trigger the scale-down half of the demo"
}
output "adopted_load_balancer_check_command" {
  value       = local.outputs.adopted_load_balancer_check_command.value
  description = "7. Lists every load balancer tagged for this cluster. One is correct; two means adoption failed silently"
}
output "dashboard_hostname_command" {
  value       = local.outputs.dashboard_hostname_command.value
  description = "8. The address the controller actually attached to the dashboard Service, for comparison against the pre-created one"
}
output "update_kubeconfig_command" {
  value       = local.outputs.update_kubeconfig_command.value
  description = "Re-points kubectl at the cluster. User data already ran this"
}
