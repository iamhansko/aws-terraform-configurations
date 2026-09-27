# Every output is a projection of local.outputs in main.tf, which is also what the
# README written onto the VS Code instance is rendered from (rules.md H-2). No value
# expression is written here: an output that built its own value would be missing
# from that README, and nothing would fail to say so - the apply would succeed
# either way. That matters more on this project than elsewhere, because the README
# is the only documentation reachable from the one machine that can talk to the
# cluster. Whether the pattern still holds is checked by counting: the number of
# output blocks here must equal the number of entries in local.outputs.
#
# description is the one thing repeated, because Terraform rejects an expression
# there ("Variables not allowed") - it has to be a literal.
output "vscode_url" {
  value       = local.outputs.vscode_url.value
  description = "URL to access the code-server web UI on the VS Code EC2 instance. The only place kubectl can reach this cluster"
}
output "cluster_name" {
  value       = local.outputs.cluster_name.value
  description = "Name of the EKS cluster"
}
output "cluster_endpoint" {
  value       = local.outputs.cluster_endpoint.value
  description = "Private API server endpoint of the EKS cluster. Resolves only inside the VPC"
}
output "ingress_url" {
  value       = local.outputs.ingress_url.value
  description = "URL of the pre-created ALB the controller adopted from the demo Ingress"
}
output "own_registry" {
  value       = local.outputs.own_registry.value
  description = "This account's ECR registry, which is the only registry the cluster can pull from"
}
output "workload_image" {
  value       = local.outputs.workload_image.value
  description = "Image reference the demo workload uses, addressed through the pull-through cache rather than as a public registry path"
}
output "endpoint_check_command" {
  value       = local.outputs.endpoint_check_command.value
  description = "Command listing the VPC endpoints and their state, which are the cluster's only path to AWS APIs"
}
output "cache_rules_check_command" {
  value       = local.outputs.cache_rules_check_command.value
  description = "Command listing the ECR pull-through cache rules"
}
output "cache_repositories_check_command" {
  value       = local.outputs.cache_repositories_check_command.value
  description = "Command listing the repositories the pull-through cache has materialised. Empty while pods are in ImagePullBackOff means the node role lacks ecr:CreateRepository and ecr:BatchImportUpstreamImage"
}
output "workload_check_command" {
  value       = local.outputs.workload_check_command.value
  description = "Command showing the demo Deployment, Service and Ingress"
}
output "controller_log_command" {
  value       = local.outputs.controller_log_command.value
  description = "Command reading the AWS Load Balancer Controller log, where a refused backend security group combination is the only place it is reported (rules.md G-2)"
}
output "adopted_load_balancer_check_command" {
  value       = local.outputs.adopted_load_balancer_check_command.value
  description = "Command listing every load balancer tagged for this cluster. One is correct; two means adoption failed and the controller built its own (rules.md G-3)"
}
output "update_kubeconfig_command" {
  value       = local.outputs.update_kubeconfig_command.value
  description = "Command that points kubectl at the cluster. Works only from inside the VPC"
}
