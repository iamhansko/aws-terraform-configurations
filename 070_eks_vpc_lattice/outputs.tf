# Every value here is a projection of local.outputs in main.tf, which the README written onto the VS Code
# instance renders from the same map - so no value expression exists twice, and an output cannot be added
# without also appearing in that README (rules.md B-5/H-2).
#
# The Lattice-assigned domain names are deliberately commands rather than values: the controller writes
# them back onto the HTTPRoutes after apply, so Terraform cannot know them (rules.md H-2).
#
# description is the one thing that cannot be projected: Terraform rejects an expression in an output's
# description ("Variables not allowed"), so the wording is a literal on both sides.
output "vscode_url" {
  value       = local.outputs.vscode_url.value
  description = "Open the IDE here. The curl commands have to be run from inside the VPC, which is what this instance is for"
}
output "cluster_name" {
  value       = local.outputs.cluster_name.value
  description = "Name of the EKS cluster, which the controller tags every Lattice resource with"
}
output "cluster_endpoint" {
  value       = local.outputs.cluster_endpoint.value
  description = "API server endpoint. Public so the helm and kubectl providers could reach it during apply"
}
output "gateway_api_install" {
  value       = local.outputs.gateway_api_install.value
  description = "The pinned Gateway API release and the pinned controller chart that implements it"
}
output "lattice_prefix_lists" {
  value       = local.outputs.lattice_prefix_lists.value
  description = "The managed prefix lists the cluster security group accepts Lattice traffic from, found with data sources rather than the original's Lambda"
}
output "service_network_check_command" {
  value       = local.outputs.service_network_check_command.value
  description = "1. Whether the controller created the VPC Lattice service network at all"
}
output "gateway_status_command" {
  value       = local.outputs.gateway_status_command.value
  description = "2. Whether the Gateway was programmed and given an address"
}
output "route_status_command" {
  value       = local.outputs.route_status_command.value
  description = "3. Whether both HTTPRoutes attached to the Gateway"
}
output "inventory_domain_command" {
  value       = local.outputs.inventory_domain_command.value
  description = "4. Reads the Lattice-assigned domain name the controller wrote back onto the inventory route"
}
output "inventory_curl_command" {
  value       = local.outputs.inventory_curl_command.value
  description = "5. Calls the inventory route from inside the cluster, which is the only place it is reachable from"
}
output "rates_curl_command" {
  value       = local.outputs.rates_curl_command.value
  description = "6. Builds the two path-routed URLs for the rates route"
}
output "controller_logs_command" {
  value       = local.outputs.controller_logs_command.value
  description = "7. The controller's log, where every reason for an unprogrammed Gateway or route lives"
}
output "target_group_check_command" {
  value       = local.outputs.target_group_check_command.value
  description = "8. The Lattice target groups and their health, which is where the security group rules show their effect"
}
output "update_kubeconfig_command" {
  value       = local.outputs.update_kubeconfig_command.value
  description = "Re-points kubectl at the cluster. User data already ran this"
}
