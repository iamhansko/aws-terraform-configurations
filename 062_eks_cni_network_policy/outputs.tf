# Every output is a projection of local.outputs in main.tf, which is also what the README
# written onto the VS Code instance is rendered from (rules.md H-2). No value expression is
# written here: an output that built its own value would be missing from that README, and
# nothing would fail to say so - the apply would succeed either way. Whether the pattern
# still holds is checked by counting: the number of output blocks here must equal the
# number of entries in local.outputs.
#
# description is the one thing repeated, because Terraform rejects an expression there
# ("Variables not allowed") - it has to be a literal.
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
output "management_ui_url" {
  value       = local.outputs.management_ui_url.value
  description = "URL of the Calico stars management UI, served through the pre-created NLB the controller adopts (rules.md G-3)"
}
output "network_policy_enforcement" {
  value       = local.outputs.network_policy_enforcement.value
  description = "Whether the VPC CNI is enforcing NetworkPolicy objects, which is the switch the entire demo depends on"
}
output "graph_check_command" {
  value       = local.outputs.graph_check_command.value
  description = "Command confirming the management UI and all three probes are running"
}
output "adopted_load_balancer_check_command" {
  value       = local.outputs.adopted_load_balancer_check_command.value
  description = "Command listing every load balancer tagged for this cluster. One is correct; two means adoption failed and the controller built its own (rules.md G-3)"
}
output "ingress_hostname_command" {
  value       = local.outputs.ingress_hostname_command.value
  description = "Command reading the address the controller attached, for comparison against the pre-created load balancer"
}
output "expected_graph" {
  value       = local.outputs.expected_graph.value
  description = "Which policies the apply created, and therefore the shape the management UI graph should have"
}
output "policy_list_command" {
  value       = local.outputs.policy_list_command.value
  description = "Command listing every NetworkPolicy currently in force"
}
output "policy_describe_command" {
  value       = local.outputs.policy_describe_command.value
  description = "Command showing which pods each policy selects and how the additive rules combine"
}
output "unrestricted_graph_command" {
  value       = local.outputs.unrestricted_graph_command.value
  description = "Command re-applying without the demo's NetworkPolicy objects, to see the fully connected graph"
}
output "update_kubeconfig_command" {
  value       = local.outputs.update_kubeconfig_command.value
  description = "Command that points kubectl on the VS Code instance at the cluster"
}
