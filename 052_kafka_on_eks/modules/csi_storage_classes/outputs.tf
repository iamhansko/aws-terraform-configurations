output "storage_class_name" {
  value       = var.storage_class_name
  description = "Name of the StorageClass, re-exposed so kube-prometheus-stack's volume claim names the same class this module created (rules.md B-5)"
}
output "storage_class_check_command" {
  value       = "kubectl get storageclass"
  description = "Lists the cluster's StorageClasses and which one is default. Exactly one line should read (default), and it should be the gp3 one with provisioner ebs.csi.aws.com"
}
