# Every value here is a projection of local.outputs in main.tf, which the README written onto the
# workbench renders from the same map - so no value expression exists twice (rules.md B-5/H-2).
#
# The descriptions are the one thing that cannot be projected: Terraform does not allow an expression
# in an output description ("Variables not allowed"), so the wording is repeated here as a literal
# while the values are not.

output "vscode_url" {
  value       = local.outputs.vscode_url.value
  description = "Open the IDE here and run every command below from its terminal. kubectl is already installed and the kubeconfig already points at the cluster"
}

output "cluster_name" {
  value       = local.outputs.cluster_name.value
  description = "Name of the EKS cluster"
}

output "cluster_endpoint" {
  value       = local.outputs.cluster_endpoint.value
  description = "API server endpoint of the EKS cluster"
}

output "pod_security_group_id" {
  value       = local.outputs.pod_security_group_id.value
  description = "The security group the SecurityGroupPolicy assigns to pods. This is the point of the project: a pod gets a branch ENI carrying this group instead of inheriting the node's"
}

output "web_ec2_private_ip" {
  value       = local.outputs.web_ec2_private_ip.value
  description = "An nginx instance in a private subnet whose security group admits only the pod security group above. Reaching it from a pod is what proves the branch ENI is in effect"
}

output "pod_eni_setting_command" {
  value       = local.outputs.pod_eni_setting_command.value
  description = "ENABLE_POD_ENI comes from the vpc-cni addon's configuration_values rather than from a kubectl set env on the DaemonSet, so it survives an addon upgrade (rules.md E-5)"
}

output "security_group_policy_command" {
  value       = local.outputs.security_group_policy_command.value
  description = "A CRD the vpc-resource-controller reconciles. It is a Terraform resource here rather than something applied by hand, which is what lets destroy remove it while that controller is still running (rules.md D-4)"
}

output "branch_eni_command" {
  value       = local.outputs.branch_eni_command.value
  description = "The pod's address is on an ENI of its own, and the interface carries the pod security group rather than the node's. An empty result with a Running pod means the policy did not match its labels"
}

output "pod_reachability_command" {
  value       = local.outputs.pod_reachability_command.value
  description = "curl from inside the pod succeeds because the instance admits the pod security group. The same curl from a node fails, which is the whole demonstration"
}

output "update_kubeconfig_command" {
  value       = local.outputs.update_kubeconfig_command.value
  description = "User data already ran this, so kubectl works out of the box. Re-run it if the kubeconfig is ever lost"
}
