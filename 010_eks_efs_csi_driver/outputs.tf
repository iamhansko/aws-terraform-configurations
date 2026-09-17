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
output "file_system_id" {
  value       = local.outputs.file_system_id.value
  description = "ID of the EFS file system the StorageClass provisions access points in"
}
output "efs_csi_driver_controller_role_arn" {
  value       = local.outputs.efs_csi_driver_controller_role_arn.value
  description = "ARN of the IAM role the EFS CSI controller assumes through IRSA"
}
output "storage_class_name" {
  value       = local.outputs.storage_class_name.value
  description = "Name of the StorageClass backed by the EFS CSI driver"
}
output "demo_claim_name" {
  value       = local.outputs.demo_claim_name.value
  description = "Name of the demo ReadWriteMany PersistentVolumeClaim, or null when create_demo_workload is false"
}
output "demo_pods_command" {
  value       = local.outputs.demo_pods_command.value
  description = "Command listing the demo pods with the nodes they landed on, or null when create_demo_workload is false"
}
output "demo_shared_file_command" {
  value       = local.outputs.demo_shared_file_command.value
  description = "Command tailing the file every demo replica appends to on the shared volume, or null when create_demo_workload is false"
}
