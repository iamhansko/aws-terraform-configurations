output "storage_class_name" {
  value       = var.storage_class_name
  description = "Name of the StorageClass, re-exposed so a workload's volumeClaimTemplate names the class that was actually created rather than restating the string (rules.md B-5). A claim naming a class that does not exist stays Pending with no volume and no error on the StatefulSet"
}
output "volume_snapshot_class_name" {
  value       = var.volume_snapshot_class_name
  description = "Name of the VolumeSnapshotClass, re-exposed so a snapshot taken by hand can name it. Velero picks it by the velero.io/csi-volumesnapshot-class label rather than by name, so this is for diagnostics rather than for wiring"
}
output "storage_class_check_command" {
  value       = "kubectl get storageclass"
  description = "The classes and which one is default. Expect the gp3 line to read (default) and the gp2 line not to. Nothing here patches gp2: EKS's built-in class carries no default-class annotation on current Kubernetes versions, and patching it is not possible anyway - see main.tf"
}
output "snapshot_class_check_command" {
  value       = "kubectl get volumesnapshotclass -o custom-columns=NAME:.metadata.name,DRIVER:.driver,DEFAULT:.metadata.annotations.snapshot\\.storage\\.kubernetes\\.io/is-default-class,VELERO:.metadata.labels.velero\\.io/csi-volumesnapshot-class"
  description = "The snapshot class with both the default annotation and the Velero label. Missing the label means Velero skips the volume when it backs up - and reports the backup as Completed anyway, which is the failure this project exists to make visible"
}
