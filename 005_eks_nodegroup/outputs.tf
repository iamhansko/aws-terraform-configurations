# Every value here is a projection of local.outputs in main.tf, which the README written onto the
# workbench renders from the same map - so no value expression exists twice (rules.md B-5/H-2).
#
# The descriptions are the one thing that cannot be projected: Terraform does not allow an expression
# in an output description ("Variables not allowed"), so the wording is repeated here as a literal
# while the values are not.

output "vscode" {
  value       = local.outputs.vscode.value
  description = "Open the IDE here and run every command below from its terminal. kubectl is already installed and the kubeconfig already points at the cluster"
}

output "eks_cluster_name" {
  value       = local.outputs.eks_cluster_name.value
  description = "Name of the EKS cluster"
}

output "eks_cluster_endpoint" {
  value       = local.outputs.eks_cluster_endpoint.value
  description = "API server endpoint of the EKS cluster"
}

output "node_group_name" {
  value       = local.outputs.node_group_name.value
  description = "The node group this project exists to show. EKS owns the Auto Scaling group behind it, which is why there is no launch template or ASG declared here"
}

output "nodes_command" {
  value       = local.outputs.nodes_command.value
  description = "Ready is the state to wait for. A node that stays NotReady is almost always missing vpc-cni or kube-proxy, which is why both addons are created before the node group (rules.md C-4)"
}

output "node_group_status_command" {
  value       = local.outputs.node_group_status_command.value
  description = "EKS reports the group's own health separately from the nodes'. DEGRADED here names the reason, which a kubectl get nodes cannot"
}

output "autoscaling_group_command" {
  value       = local.outputs.autoscaling_group_command.value
  description = "Not declared anywhere in this configuration - the node group owns it. Scaling it by hand is what the managed group's update path exists to avoid"
}

output "update_kubeconfig_command" {
  value       = local.outputs.update_kubeconfig_command.value
  description = "User data already ran this, so kubectl works out of the box. Re-run it if the kubeconfig is ever lost"
}
