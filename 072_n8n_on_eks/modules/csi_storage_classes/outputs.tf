output "storage_class_name" {
  value       = var.storage_class_name
  description = "Name of the StorageClass, re-exposed so a workload's claim names the class that was actually created rather than restating the string (rules.md B-5). A claim naming a class that does not exist stays Pending with no volume and no error on the Deployment"
}
output "volume_snapshot_class_name" {
  value       = var.create_volume_snapshot_class ? var.volume_snapshot_class_name : null
  description = "Name of the VolumeSnapshotClass, or null when none was created. Re-exposed so a caller can tell which of the two it got rather than assuming (rules.md B-5)"
}
output "storage_class_check_command" {
  value       = "kubectl get storageclass"
  description = "The classes and which one is default. Expect the gp3 line to read (default) and the gp2 line not to. Nothing here patches gp2: EKS's built-in class carries no default-class annotation on current Kubernetes versions, and patching it is not possible anyway - see main.tf"
}
