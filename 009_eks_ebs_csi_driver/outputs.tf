# Every output is a projection of local.outputs in main.tf, which is also what
# the README on the instance is rendered from (rules.md H-2). No value
# expression is written here: an output that built its own value would be
# missing from that README, and nothing would fail to tell anyone.
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
output "ebs_csi_driver_controller_role_arn" {
  value       = local.outputs.ebs_csi_driver_controller_role_arn.value
  description = "ARN of the IAM role the EBS CSI controller assumes through IRSA"
}
output "storage_class_name" {
  value       = local.outputs.storage_class_name.value
  description = "Name of the StorageClass backed by the EBS CSI driver"
}
output "demo_claim_name" {
  value       = local.outputs.demo_claim_name.value
  description = "Name of the demo PersistentVolumeClaim, or null when create_demo_workload is false"
}
output "demo_claim_status_command" {
  value       = local.outputs.demo_claim_status_command.value
  description = "Command showing the demo claim's bind status, or null when create_demo_workload is false"
}
output "demo_pods_command" {
  value       = local.outputs.demo_pods_command.value
  description = "Command listing the demo pods with the nodes they landed on, or null when create_demo_workload is false"
}
output "demo_volume_file_command" {
  value       = local.outputs.demo_volume_file_command.value
  description = "Command tailing the file the demo writes onto the provisioned volume, or null when create_demo_workload is false"
}
