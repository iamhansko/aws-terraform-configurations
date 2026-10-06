# Every value here is a projection of local.outputs in main.tf. No output in this
# file builds its own expression: the same map feeds the README written onto the
# workbench, and an output declared outside it would be missing from that README
# with nothing to signal the gap (rules.md H-2).
#
# description is the one thing that cannot come from the map. Terraform rejects an
# expression in an output's description ("Variables not allowed"), so the wording
# is literal in both places while the value stays in one.

output "vscode_url" {
  value       = local.outputs.vscode_url.value
  description = "URL of the code-server web UI on the workbench instance"
}

output "cluster_name" {
  value       = local.outputs.cluster_name.value
  description = "Name of the EKS cluster. It has no node group at all - every pod in it runs on Fargate"
}

output "cluster_endpoint" {
  value       = local.outputs.cluster_endpoint.value
  description = "API server endpoint. Public and private are both on, which is what lets the kubectl and helm providers apply this project's Kubernetes objects from outside the VPC"
}

output "fargate_profile_name" {
  value       = local.outputs.fargate_profile_name.value
  description = "Name of the single Fargate profile, which selects both kube-system and default"
}

output "efs_file_system_id" {
  value       = local.outputs.efs_file_system_id.value
  description = "ID of the EFS file system, which is the volumeHandle both PersistentVolumes name"
}

output "efs_dns_name" {
  value       = local.outputs.efs_dns_name.value
  description = "DNS name of the EFS file system, resolving to the mount target in the caller's availability zone"
}

output "fargate_nodes_command" {
  value       = local.outputs.fargate_nodes_command.value
  description = "Command that lists the nodes with their compute type, which should be fargate for every entry"
}

output "coredns_status_command" {
  value       = local.outputs.coredns_status_command.value
  description = "Command that shows whether the CoreDNS replicas became ready on Fargate"
}

output "persistent_volume_claim_status_command" {
  value       = local.outputs.persistent_volume_claim_status_command.value
  description = "Command that shows whether both persistent volume claims reached Bound"
}

output "pod_status_command" {
  value       = local.outputs.pod_status_command.value
  description = "Command that shows the writer and reader pods and the Fargate node each landed on"
}

output "shared_file_read_command" {
  value       = local.outputs.shared_file_read_command.value
  description = "Command that reads, from the reader pod, the file the writer pod appends to through a separate PersistentVolume"
}

output "write_pod_log_command" {
  value       = local.outputs.write_pod_log_command.value
  description = "Command that shows the writer pod's own output, for telling a mount problem apart from a scheduling problem"
}

output "load_balancer_controller_status_command" {
  value       = local.outputs.load_balancer_controller_status_command.value
  description = "Command that shows the AWS Load Balancer Controller Deployment, which this project installs but does not use"
}

output "update_kubeconfig_command" {
  value       = local.outputs.update_kubeconfig_command.value
  description = "Command that points kubectl on the workbench at the cluster"
}
