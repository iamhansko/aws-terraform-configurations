output "persistent_volume_name" {
  value       = var.persistent_volume_name
  description = "Name of the statically provisioned PersistentVolume, re-exposed so callers share one source of truth (rules.md B-5)"
}
output "claim_name" {
  value       = var.claim_name
  description = "Name of the PersistentVolumeClaim bound to the volume"
}
output "mount_options" {
  value       = local.mount_options
  description = "Mount options rendered onto the PersistentVolume, so what Mountpoint was actually told is visible without reading the manifest back out of the cluster"
}
output "demo_pod_name" {
  value       = var.create_demo_pod ? var.demo_pod_name : null
  description = "Name of the demo pod, or null when create_demo_pod is false"
}
output "demo_pod_files_command" {
  value       = var.create_demo_pod ? "kubectl -n ${var.namespace} exec ${var.demo_pod_name} -- ls -l ${var.demo_mount_path}" : null
  description = "Command listing the mounted bucket contents from inside the pod"
}
output "bucket_objects_command" {
  value       = "aws s3 ls s3://${var.bucket_name}/${var.prefix == null ? "" : var.prefix}"
  description = "Command listing the same objects through the S3 API, which is what shows the pod's writes really landed in the bucket rather than in a container filesystem"
}
