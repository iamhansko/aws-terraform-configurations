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
output "coredns_autoscaling" {
  value       = local.outputs.coredns_autoscaling.value
  description = "Replica range the coredns addon manages itself, or 'disabled' when native autoscaling is off"
}
output "node_group_range" {
  value       = local.outputs.node_group_range.value
  description = "Node group size range the addon scales CoreDNS against"
}
output "coredns_replicas_command" {
  value       = local.outputs.coredns_replicas_command.value
  description = "Command watching the CoreDNS Deployment's replica count, which is what this variant demonstrates"
}
output "scale_nodes_command" {
  value       = local.outputs.scale_nodes_command.value
  description = "Command scaling the node group, which is what makes the addon adjust CoreDNS"
}
output "no_autoscaler_pod_command" {
  value       = local.outputs.no_autoscaler_pod_command.value
  description = "Command confirming no autoscaler Deployment exists, unlike the cpa_coredns variant"
}
output "addon_status_command" {
  value       = local.outputs.addon_status_command.value
  description = "Command reading the coredns addon's status and the configuration_values EKS holds for it"
}
output "top_pods_command" {
  value       = local.outputs.top_pods_command.value
  description = "Command showing CoreDNS pod resource use, via the metrics-server addon"
}
output "update_kubeconfig_command" {
  value       = local.outputs.update_kubeconfig_command.value
  description = "Command that points kubectl on the VS Code instance at the cluster"
}
