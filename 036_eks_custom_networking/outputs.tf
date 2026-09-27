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
output "vpc_cidr_block" {
  value       = local.outputs.vpc_cidr_block.value
  description = "Primary VPC CIDR, which node addresses come from"
}
output "secondary_cidr_block" {
  value       = local.outputs.secondary_cidr_block.value
  description = "Secondary VPC CIDR, which pod addresses come from under custom networking"
}
output "ingress_url" {
  value       = local.outputs.ingress_url.value
  description = "URL of the pre-created ALB the controller adopted from the demo Ingress"
}
output "pod_address_check_command" {
  value       = local.outputs.pod_address_check_command.value
  description = "Command comparing the demo workload's pod addresses against its nodes' addresses"
}
output "eni_config_check_command" {
  value       = local.outputs.eni_config_check_command.value
  description = "Command listing the ENIConfig custom resources, one per availability zone"
}
output "all_pod_address_check_command" {
  value       = local.outputs.all_pod_address_check_command.value
  description = "Command showing every pod's address, including system pods that predate custom networking"
}
output "ingress_hostname_command" {
  value       = local.outputs.ingress_hostname_command.value
  description = "Command reading the address the controller attached, for comparison against the pre-created ALB"
}
output "adopted_load_balancer_check_command" {
  value       = local.outputs.adopted_load_balancer_check_command.value
  description = "Command listing every load balancer tagged for this cluster. One is correct; two means adoption failed (rules.md G-3)"
}
output "update_kubeconfig_command" {
  value       = local.outputs.update_kubeconfig_command.value
  description = "Command that points kubectl on the VS Code instance at the cluster"
}
