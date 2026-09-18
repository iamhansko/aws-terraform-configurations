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
output "default_fargate_profile_name" {
  value       = local.outputs.default_fargate_profile_name.value
  description = "Name of the Fargate profile selecting the default namespace"
}
output "kubesystem_fargate_profile_name" {
  value       = local.outputs.kubesystem_fargate_profile_name.value
  description = "Name of the Fargate profile selecting kube-system, which is what CoreDNS runs on"
}
output "coredns_status_command" {
  value       = local.outputs.coredns_status_command.value
  description = "Command showing whether CoreDNS is actually running. Pending replicas mean the addon's computeType is not Fargate"
}
output "fargate_nodes_command" {
  value       = local.outputs.fargate_nodes_command.value
  description = "Command listing the cluster's nodes with their compute type. All of them should be Fargate"
}
output "demo_pod_command" {
  value       = local.outputs.demo_pod_command.value
  description = "Command running a pod in the default namespace, which the default-fargate profile places on Fargate"
}
output "demo_pod_cleanup_command" {
  value       = local.outputs.demo_pod_cleanup_command.value
  description = "Command deleting the demo pod. Fargate bills per pod, so this is worth running when the demo is over"
}
output "update_kubeconfig_command" {
  value       = local.outputs.update_kubeconfig_command.value
  description = "Command that points kubectl on the VS Code instance at the cluster. User data already ran it; this is for recovering a lost kubeconfig"
}
