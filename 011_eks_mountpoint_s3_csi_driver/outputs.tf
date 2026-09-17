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
output "bucket_name" {
  value       = local.outputs.bucket_name.value
  description = "Name of the S3 bucket the Mountpoint driver mounts into the pod"
}
output "driver_role_arn" {
  value       = local.outputs.driver_role_arn.value
  description = "ARN of the IAM role the Mountpoint S3 CSI driver assumes through IRSA, scoped to the bucket above"
}
output "persistent_volume_name" {
  value       = local.outputs.persistent_volume_name.value
  description = "Name of the statically provisioned PersistentVolume backed by the bucket"
}
output "claim_name" {
  value       = local.outputs.claim_name.value
  description = "Name of the PersistentVolumeClaim pre-bound to that volume"
}
output "mount_options" {
  value       = local.outputs.mount_options.value
  description = "Mountpoint mount options rendered onto the PersistentVolume, as a comma-separated list"
}
output "demo_pod_files_command" {
  value       = local.outputs.demo_pod_files_command.value
  description = "Command listing the mounted bucket contents from inside the demo pod, or null when create_demo_pod is false"
}
output "bucket_objects_command" {
  value       = local.outputs.bucket_objects_command.value
  description = "Command listing the same objects through the S3 API, showing the pod's writes landed in the bucket"
}
