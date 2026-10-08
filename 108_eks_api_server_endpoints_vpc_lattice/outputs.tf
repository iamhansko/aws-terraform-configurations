# Every value here is a projection of local.outputs in main.tf, which the README written onto the workbench
# renders from the same map - so no value expression exists twice, and an output cannot be added without also
# appearing in that README (rules.md B-5/H-2).
#
# description is the one thing that cannot be projected: Terraform rejects an expression in an output's
# description ("Variables not allowed"), so the wording is a literal on both sides.
output "vscode_url" {
  value       = local.outputs.vscode_url.value
  description = "Open the IDE here. It runs in the client VPC and reaches the private API server through VPC Lattice"
}
output "what_this_shows" {
  value       = local.outputs.what_this_shows.value
  description = "The path from the client VPC to a private API server, with no peering and no transit gateway"
}
output "api_server_endpoint" {
  value       = local.outputs.api_server_endpoint.value
  description = "The cluster's endpoint. Private only, which is what the rest of this project exists to reach"
}
output "resolve_command" {
  value       = local.outputs.resolve_command.value
  description = "1. Whether the API server's name resolves to the Lattice endpoint inside the client VPC"
}
output "kubectl_command" {
  value       = local.outputs.kubectl_command.value
  description = "2. Whether the API server answers. Resolving but timing out points at the security groups"
}
output "lattice_configuration_command" {
  value       = local.outputs.lattice_configuration_command.value
  description = "3. The resource configuration, its status and what it forwards"
}
output "lattice_association_command" {
  value       = local.outputs.lattice_association_command.value
  description = "4. Whether the configuration is attached to the service network"
}
output "endpoint_associations_command" {
  value       = local.outputs.endpoint_associations_command.value
  description = "5. The DNS name the endpoint publishes - the call the deleted Lambda existed to make"
}
output "endpoint_state_command" {
  value       = local.outputs.endpoint_state_command.value
  description = "6. Whether the endpoint came up"
}
output "private_dns" {
  value       = local.outputs.private_dns.value
  description = "The private hosted zone that makes the cluster's own hostname resolve in the client VPC"
}
output "cluster_name" {
  value       = local.outputs.cluster_name.value
  description = "Name of the EKS cluster"
}
output "update_kubeconfig_command" {
  value       = local.outputs.update_kubeconfig_command.value
  description = "Re-points kubectl at the cluster. An SSM association already ran it after the endpoint existed"
}
output "private_key_command" {
  value       = local.outputs.private_key_command.value
  description = "Reads the workbench's SSH private key out of SSM Parameter Store"
}
