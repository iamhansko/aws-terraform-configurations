output "namespace" {
  value       = var.namespace
  description = "Namespace the demo objects live in, re-exposed so the caller's verification commands do not restate it (rules.md B-5)"
}

output "write_pod_name" {
  value       = var.write_pod_name
  description = "Name of the writer pod"
}

output "read_pod_name" {
  value       = var.read_pod_name
  description = "Name of the reader pod"
}

output "persistent_volume_claim_status_command" {
  value       = "kubectl -n ${var.namespace} get pvc ${var.write_claim_name} ${var.read_claim_name}"
  description = "Command that shows whether both claims reached Bound. A claim stuck at Pending is the failure mode of static provisioning: capacity, access mode or storage class did not match its volume"
}

output "pod_status_command" {
  value       = "kubectl -n ${var.namespace} get pods ${var.write_pod_name} ${var.read_pod_name} -o wide"
  description = "Command that shows both pods and, in the NODE column, the fargate-ip-* name that proves they are on Fargate rather than on a node"
}

output "shared_file_read_command" {
  value       = "kubectl -n ${var.namespace} exec ${var.read_pod_name} -- tail -n 5 ${var.mount_path}/${var.output_file_name}"
  description = "The verification step: the reader pod prints lines the writer pod appended, through two separate PersistentVolumes onto one EFS file system"
}

output "write_pod_log_command" {
  value       = "kubectl -n ${var.namespace} logs ${var.write_pod_name}"
  description = "Command that shows the writer pod's own output, useful when the shared file is empty and the question is whether the writer ever started"
}
