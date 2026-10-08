# Every value here is a projection of local.outputs in main.tf. No output in this file builds its
# own expression: the same map feeds the README written onto both workbenches, and an output declared
# outside it would be missing from those READMEs with nothing to signal the gap (rules.md H-2).
#
# description is the one thing that cannot come from the map. Terraform rejects an expression in an
# output's description ("Variables not allowed"), so the wording is literal in both places while the
# value stays in one.

output "vpc_a_vscode_url" {
  value       = local.outputs.vpc_a_vscode_url.value
  description = "The workbench for VPC A's cluster"
}

output "vpc_b_vscode_url" {
  value       = local.outputs.vpc_b_vscode_url.value
  description = "The workbench for VPC B's cluster"
}

output "vpc_a_url" {
  value       = local.outputs.vpc_a_url.value
  description = "The pre-created ALB in VPC A"
}

output "vpc_b_url" {
  value       = local.outputs.vpc_b_url.value
  description = "The pre-created ALB in VPC B"
}

output "address_plan" {
  value       = local.outputs.address_plan.value
  description = "The routable primary blocks differ; the non-routable secondary block is the same in both VPCs on purpose"
}

output "transit_gateway_routes_command" {
  value       = local.outputs.transit_gateway_routes_command.value
  description = "Two routes, one per VPC, both active"
}

output "vpc_a_route_tables_command" {
  value       = local.outputs.vpc_a_route_tables_command.value
  description = "This is where the design is visible: the node tier reaches VPC B through a private NAT gateway, while the private tier reaches it through the transit gateway directly"
}

output "vpc_a_pods_command" {
  value       = local.outputs.vpc_a_pods_command.value
  description = "Every address is in 100.64/16"
}

output "vpc_a_ingress_command" {
  value       = local.outputs.vpc_a_ingress_command.value
  description = "Compare the address this prints against the VPC A URL above"
}

output "cross_vpc_request_command" {
  value       = local.outputs.cross_vpc_request_command.value
  description = "The demonstration"
}

output "reverse_request_command" {
  value       = local.outputs.reverse_request_command.value
  description = "Same path in reverse, from VPC B's cluster to VPC A's ALB"
}

output "private_nat_addresses" {
  value       = local.outputs.private_nat_addresses.value
  description = "What a packet capture or a security group rule in the other VPC observes as the source - not the pod's address"
}

output "attachments_check_command" {
  value       = local.outputs.attachments_check_command.value
  description = "An attachment placed in the non-routable tier is created, reports available, and is unreachable from the other side - a timeout rather than an error"
}
