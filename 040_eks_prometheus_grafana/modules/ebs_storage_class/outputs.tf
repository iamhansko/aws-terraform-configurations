output "storage_class_name" {
  value       = var.storage_class_name
  description = "Name of the created StorageClass, re-exposed so callers referencing it in their own claims share one source of truth (rules.md B-5)"
}
output "demo_claim_name" {
  value       = var.create_demo_workload ? var.demo_claim_name : null
  description = "Name of the demo PersistentVolumeClaim, or null when create_demo_workload is false"
}
output "demo_deployment_name" {
  value       = var.create_demo_workload ? var.demo_deployment_name : null
  description = "Name of the demo Deployment, or null when create_demo_workload is false"
}
output "demo_claim_status_command" {
  value       = var.create_demo_workload ? "kubectl -n ${var.namespace} get pvc ${var.demo_claim_name}" : null
  description = "Command showing the claim's bind status. With WaitForFirstConsumer it stays Pending until a pod is scheduled, which is the behaviour worth seeing rather than a bug"
}
output "demo_pods_command" {
  value       = var.create_demo_workload ? "kubectl -n ${var.namespace} get pods -l app=${var.demo_deployment_name} -o wide" : null
  description = "Command listing the demo pods with their nodes. Every replica lands on the same node, because a ReadWriteOnce EBS volume can only attach to one"
}
output "demo_volume_file_command" {
  value       = var.create_demo_workload ? "kubectl -n ${var.namespace} exec deploy/${var.demo_deployment_name} -- tail -n 20 /data/out.txt" : null
  description = "Command tailing the file the demo writes onto the provisioned volume, which is what confirms dynamic provisioning worked end to end"
}
