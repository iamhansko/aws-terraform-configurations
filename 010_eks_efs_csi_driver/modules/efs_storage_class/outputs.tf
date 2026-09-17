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
output "demo_pods_command" {
  value       = var.create_demo_workload ? "kubectl -n ${var.namespace} get pods -l app=${var.demo_deployment_name} -o wide" : null
  description = "Command listing the demo pods with the nodes they landed on, showing the replicas spread across nodes while sharing one volume"
}
output "demo_shared_file_command" {
  value       = var.create_demo_workload ? "kubectl -n ${var.namespace} exec deploy/${var.demo_deployment_name} -- tail -n 20 /data/out" : null
  description = "Command showing the tail of the shared file, where interleaved hostnames prove every replica writes to the same volume"
}
