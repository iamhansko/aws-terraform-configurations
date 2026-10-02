# Every value here is a projection of local.outputs in main.tf. No output declares its
# own value expression: the same map is what the README on the VS Code instance is
# rendered from, so an output written directly here would be missing from that README and
# nothing would report it - the apply succeeds either way (rules.md H-2).
#
# description is the one exception. Terraform does not allow an expression there
# ("Variables not allowed"), so the wording exists as a literal in both places while the
# value still exists in only one.
output "vscode_url" {
  value       = local.outputs.vscode_url.value
  description = "Open the IDE here. The commands below are meant to be run from its terminal, which is where the cilium CLI is installed"
}
output "cluster_name" {
  value       = local.outputs.cluster_name.value
  description = "Name of the EKS cluster, which the controller also writes into the elbv2.k8s.aws/cluster tag on load balancers it owns"
}
output "cluster_endpoint" {
  value       = local.outputs.cluster_endpoint.value
  description = "API server endpoint, and what the Cilium agent is pointed at directly because kube-proxy is not there to translate the in-cluster Service address"
}
output "data_plane" {
  value       = local.outputs.data_plane.value
  description = "Cilium's version, IPAM mode and kube-proxy replacement setting - the three things that decide whether this cluster behaves as the project intends"
}
output "game_url" {
  value       = local.outputs.game_url.value
  description = "The demo workload through the pre-created ALB. Known from state because Terraform created the load balancer and the controller adopted it (rules.md G-3)"
}
output "cilium_status_command" {
  value       = local.outputs.cilium_status_command.value
  description = "Cilium's own summary of agent and operator health, IPAM mode and kube-proxy replacement"
}
output "kube_proxy_absence_command" {
  value       = local.outputs.kube_proxy_absence_command.value
  description = "Confirms neither kube-proxy nor aws-node exists. Both present is what the _monolithic template silently produced"
}
output "pod_address_command" {
  value       = local.outputs.pod_address_command.value
  description = "Confirms pod addresses are VPC addresses, which is what makes an ALB with target-type ip able to reach them"
}
output "interface_check_command" {
  value       = local.outputs.interface_check_command.value
  description = "The interfaces Cilium's operator attached, seen from the VPC's side"
}
output "operator_role_arn" {
  value       = local.outputs.operator_role_arn.value
  description = "IRSA role the Cilium operator assumes to attach interfaces. Wider than AmazonEKS_CNI_Policy, which lacks two Describe actions Cilium needs"
}
output "service_routing_command" {
  value       = local.outputs.service_routing_command.value
  description = "The Service backends Cilium is load balancing in place of kube-proxy"
}
output "adopted_load_balancer_check_command" {
  value       = local.outputs.adopted_load_balancer_check_command.value
  description = "Lists every load balancer tagged for this cluster. One is correct; two means the pre-created one was not adopted (rules.md G-3)"
}
output "ingress_hostname_command" {
  value       = local.outputs.ingress_hostname_command.value
  description = "The address the controller attached to the Ingress, for comparison against game_url"
}
output "connectivity_test_command" {
  value       = local.outputs.connectivity_test_command.value
  description = "Cilium's end-to-end test suite. Left as a command because it creates and deletes its own namespace"
}
output "update_kubeconfig_command" {
  value       = local.outputs.update_kubeconfig_command.value
  description = "Re-points kubectl on the instance at the cluster. User data already ran this"
}
