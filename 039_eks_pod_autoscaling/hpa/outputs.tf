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
output "hpa_target" {
  value       = local.outputs.hpa_target.value
  description = "The CPU utilisation target the HPA holds, together with the request it is measured against"
}
output "hpa_replica_range" {
  value       = local.outputs.hpa_replica_range.value
  description = "Replica range the HPA may move the Deployment within"
}
output "node_group_range" {
  value       = local.outputs.node_group_range.value
  description = "Node group size range, which nothing scales automatically in this variant"
}
output "hpa_watch_command" {
  value       = local.outputs.hpa_watch_command.value
  description = "Command watching the HPA's observed utilisation and replica count"
}
output "node_viewer_command" {
  value       = local.outputs.node_viewer_command.value
  description = "Command running eks-node-viewer on the VS Code instance to watch pods land on nodes"
}
output "load_generator_command" {
  value       = local.outputs.load_generator_command.value
  description = "Command creating the load generator pod that drives the scale-up"
}
output "pods_command" {
  value       = local.outputs.pods_command.value
  description = "Command listing the workload's pods and the nodes they landed on"
}
output "load_generator_cleanup_command" {
  value       = local.outputs.load_generator_cleanup_command.value
  description = "Command removing the load generator, after which the HPA scales back down"
}
output "update_kubeconfig_command" {
  value       = local.outputs.update_kubeconfig_command.value
  description = "Command that points kubectl on the VS Code instance at the cluster"
}
