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
output "storage_class_name" {
  value       = local.outputs.storage_class_name.value
  description = "Name of the default StorageClass backed by the EBS CSI driver"
}
output "kubecost_url" {
  value       = local.outputs.kubecost_url.value
  description = "URL of the pre-created load balancer fronting the Kubecost dashboard"
}
output "kubecost_basic_auth_user" {
  value       = local.outputs.kubecost_basic_auth_user.value
  description = "Username for the dashboard's HTTP basic auth. The password is deliberately not an output: it is supplied as a sensitive variable and is not written into the instance README (rules.md H-2)"
}
output "kubecost_rollout_command" {
  value       = local.outputs.kubecost_rollout_command.value
  description = "Command confirming the cost-analyzer finished rolling out"
}
output "kubecost_ingress_check_command" {
  value       = local.outputs.kubecost_ingress_check_command.value
  description = "Command showing the dashboard Ingress and the address it got"
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
