# Every output is a projection of local.outputs in main.tf, which is also what
# the README written onto the VS Code instance is rendered from (rules.md H-2).
# No value expression is written here: an output that built its own value would
# be missing from that README, and nothing would fail to tell anyone - the apply
# would succeed either way. Whether this pattern still holds is checked by
# counting: the number of output blocks here must equal the number of entries in
# local.outputs.
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
  description = "API server endpoint of the EKS cluster. Private only, so it is reachable from the VPC and nowhere else"
}
output "node_role_arn" {
  value       = local.outputs.node_role_arn.value
  description = "ARN of the role the nodes Auto Mode launches carry"
}
output "nodepool_command" {
  value       = local.outputs.nodepool_command.value
  description = "Command listing the built-in Auto Mode node pools"
}
output "nodes_command" {
  value       = local.outputs.nodes_command.value
  description = "Command listing nodes. Empty until a workload needs capacity"
}
output "demo_deployment_command" {
  value       = local.outputs.demo_deployment_command.value
  description = "Command creating a demo Deployment, which is what makes Auto Mode launch a node"
}
output "demo_service_command" {
  value       = local.outputs.demo_service_command.value
  description = "Command exposing the demo through a LoadBalancer Service, reconciled by Auto Mode's built-in controller"
}
output "demo_cleanup_command" {
  value       = local.outputs.demo_cleanup_command.value
  description = "Command removing the demo Service and Deployment"
}
output "update_kubeconfig_command" {
  value       = local.outputs.update_kubeconfig_command.value
  description = "Command that points kubectl on the VS Code instance at the cluster. User data already ran it; this is for recovering a lost kubeconfig"
}
