output "release_name" {
  value       = helm_release.velero.name
  description = "Name of the release"
}
output "namespace" {
  value       = var.namespace
  description = "Namespace Velero runs in, re-exposed so the caller's diagnostic commands read one value (rules.md B-5)"
}
output "chart_version" {
  value       = var.chart_version
  description = "Chart version installed. Not the Velero version - chart 12.2.0 carries Velero 1.18.2"
}
output "plugin_image" {
  value       = "${var.plugin_image_repository}:${var.plugin_image_tag}"
  description = "The AWS plugin image the init container loads, re-exposed because its version has to match the Velero version the chart carries and a mismatch shows up only as a BackupStorageLocation stuck Unavailable"
}
output "role_arn" {
  value       = aws_iam_role.velero.arn
  description = "ARN of Velero's IAM role. Its S3 permissions are scoped to the one backup bucket, where the _monolithic template granted them on every bucket in the account"
}
output "backup_storage_location_name" {
  value       = var.backup_storage_location_name
  description = "Name of the BackupStorageLocation the chart created, re-exposed so a backup command can name it explicitly (rules.md B-5)"
}
output "bucket_name" {
  value       = var.bucket_name
  description = "The bucket this Velero writes to, re-exposed so two installations can be compared. In the cross-account variants they differ by design; in the cluster variant they are deliberately the same, which is what lets one cluster restore the other's backup"
}
output "status_command" {
  value       = "kubectl -n ${var.namespace} get deployment ${var.release_name},daemonset -o wide"
  description = "The server Deployment and the node agent DaemonSet. The DaemonSet is the part people forget: without it a backup with --snapshot-move-data puts nothing in the bucket, and reports success"
}
output "backup_location_check_command" {
  value       = "kubectl -n ${var.namespace} get backupstoragelocation,volumesnapshotlocation -o wide"
  description = "Whether Velero can actually reach the bucket. PHASE must be Available - Unavailable means either the plugin image is missing, the region in the config is wrong, or the Pod Identity association is not being used. This is the first thing to read after an apply"
}
output "log_command" {
  value       = "kubectl -n ${var.namespace} logs deploy/${var.release_name} --tail 200"
  description = "What Velero did. An AccessDenied here is the Pod Identity association; a NoSuchBucket is the backupStorageLocation; a snapshot that never completes is the snapshot-controller addon"
}
output "backup_command" {
  value       = "velero backup create <name> --snapshot-move-data --include-namespaces default --exclude-resources targetgroupbindings.elbv2.k8s.aws --wait"
  description = "--snapshot-move-data puts the volume contents in the bucket. TargetGroupBinding is excluded because it is controller-owned and contains a target group ARN tied to the source account and region; the destination controller must recreate it from the restored Service"
}
output "restore_command" {
  value       = "velero restore create --from-backup <name> --exclude-resources targetgroupbindings.elbv2.k8s.aws --wait"
  description = "Run this against the other cluster context after velero backup get shows the backup. Excluding the controller-owned TargetGroupBinding also makes restores safe for older backups that captured a source-account target group ARN; the restored Service makes the destination controller create a local replacement"
}
