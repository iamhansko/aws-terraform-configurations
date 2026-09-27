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
output "prefix_delegation_settings" {
  value       = local.outputs.prefix_delegation_settings.value
  description = "The prefix delegation environment the vpc-cni addon was configured with"
}
output "node_max_pods" {
  value       = local.outputs.node_max_pods.value
  description = "Kubelet max-pods limit set on each node through the launch template's NodeConfig. Prefix delegation alone does not raise this"
}
output "ingress_url" {
  value       = local.outputs.ingress_url.value
  description = "URL of the pre-created ALB the controller adopted from the demo Ingress"
}
output "pod_count_command" {
  value       = local.outputs.pod_count_command.value
  description = "Command counting the running replicas, which is the measurement this project exists to make"
}
output "node_capacity_command" {
  value       = local.outputs.node_capacity_command.value
  description = "Command reading each node's allocatable pod count as the kubelet reports it"
}
output "pending_pods_command" {
  value       = local.outputs.pending_pods_command.value
  description = "Command listing Pending pods. Empty is the healthy case; anything here distinguishes a kubelet limit from a CNI address problem"
}
output "cni_env_command" {
  value       = local.outputs.cni_env_command.value
  description = "Command showing the prefix delegation variables as the aws-node DaemonSet actually has them"
}
output "adopted_load_balancer_check_command" {
  value       = local.outputs.adopted_load_balancer_check_command.value
  description = "Command listing every load balancer tagged for this cluster. One is correct; two means adoption failed (rules.md G-3)"
}
output "update_kubeconfig_command" {
  value       = local.outputs.update_kubeconfig_command.value
  description = "Command that points kubectl on the VS Code instance at the cluster"
}
