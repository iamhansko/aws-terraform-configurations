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
  description = "Open the IDE here. The kubectl commands below are meant to be run from its terminal"
}
output "cluster_name" {
  value       = local.outputs.cluster_name.value
  description = "Name of the EKS cluster"
}
output "cluster_endpoint" {
  value       = local.outputs.cluster_endpoint.value
  description = "API server endpoint. Public so the kubectl provider could reach it during apply - narrow public_access_cidrs to your own address"
}
output "primary_subnets" {
  value       = local.outputs.primary_subnets.value
  description = "The subnets the worker nodes launch into, with their usable address counts. Deliberately far too small for the pods that will run on them"
}
output "cni_subnets" {
  value       = local.outputs.cni_subnets.value
  description = "The tagged subnets, carved out of a second CIDR added to the same VPC, that the CNI allocates pod addresses from once a node's own subnet is empty"
}
output "cni_discovery_tag" {
  value       = local.outputs.cni_discovery_tag.value
  description = "The tag the subnets carry. Nothing validates it: a subnet without it is never considered, with no error anywhere"
}
output "subnet_discovery_setting" {
  value       = local.outputs.subnet_discovery_setting.value
  description = "The JSON the vpc-cni addon was configured with, so a value that landed in the wrong place is visible rather than silently ignored (rules.md E-5)"
}
output "rollout_status_command" {
  value       = local.outputs.rollout_status_command.value
  description = "Waits for the pressure workload. A pod still waiting for an address looks exactly like one that was never scheduled, so run this before reading anything else"
}
output "address_distribution_command" {
  value       = local.outputs.address_distribution_command.value
  description = "Counts pod addresses by range. Two groups - 10.0 and 100.64 - is the demo working"
}
output "pod_status_command" {
  value       = local.outputs.pod_status_command.value
  description = "Every pressure pod with its address and node, sorted by address so the two ranges appear as two blocks"
}
output "subnet_check_command" {
  value       = local.outputs.subnet_check_command.value
  description = "Lists subnets through the same tag filter the CNI uses, with the free address count it ranks them by"
}
output "interface_check_command" {
  value       = local.outputs.interface_check_command.value
  description = "Shows which subnet each network interface is in: pod interfaces in the tagged subnets, nodes still in the private ones"
}
output "subnet_discovery_check_command" {
  value       = local.outputs.subnet_discovery_check_command.value
  description = "Confirms the environment variable reached the aws-node DaemonSet. Empty output means the CNI is using its own default rather than this project's setting"
}
output "pending_pods_command" {
  value       = local.outputs.pending_pods_command.value
  description = "Pods that never got an address. Empty is expected, and a non-empty result is what address exhaustion looks like from Kubernetes"
}
output "cni_log_command" {
  value       = local.outputs.cni_log_command.value
  description = "The CNI agent's own account of which subnets it considered and chose. Where a tag typo shows up"
}
output "raise_pressure_command" {
  value       = local.outputs.raise_pressure_command.value
  description = "Raises the pod count through Terraform, so the value lives in state instead of being undone by the next apply (rules.md B-4)"
}
output "update_kubeconfig_command" {
  value       = local.outputs.update_kubeconfig_command.value
  description = "Re-points kubectl on the instance at the cluster. User data already ran this"
}
