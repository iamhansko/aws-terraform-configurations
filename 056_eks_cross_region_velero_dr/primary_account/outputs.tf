# Values are all projections of local.outputs in main.tf, so no expression is written twice and the
# README the SSM association writes cannot fall behind this file (rules.md B-5/H-2).
#
# description is the one thing that cannot come from the map: Terraform rejects an expression in an
# output's description with "Variables not allowed", so the wording exists literally in both places.
# The values do not.
output "apply_order" {
  value       = local.outputs.apply_order.value
  description = "secondary_account must already be applied, with that account's credentials. S3 rejects a replication configuration whose destination bucket does not exist, and the rejection happens partway through this apply rather than in plan"
}
output "vscode_url" {
  value       = local.outputs.vscode_url.value
  description = "Open the IDE here. The restore side has its own workbench in the other account - there is no single place from which both can be driven"
}
output "agreed_names" {
  value       = local.outputs.agreed_names.value
  description = "The only two things crossing the account boundary, and they cross as literal strings. secondary_account's replication_source_role_name must equal the role name and its secondary_bucket_name must equal the destination bucket"
}
output "replication_role_arn" {
  value       = local.outputs.replication_role_arn.value
  description = "The exact role ARN the other account's bucket policy must carry in its aws:PrincipalArn condition. The Principal is this account's root ARN so the policy can exist before the role"
}
output "velero_status_command" {
  value       = local.outputs.velero_status_command.value
  description = "The BackupStorageLocation must say Available: Unavailable means the plugin image is missing, the bucket region is wrong, or the Pod Identity association is not being used"
}
output "snapshot_class_check_command" {
  value       = local.outputs.snapshot_class_check_command.value
  description = "Velero picks a VolumeSnapshotClass by the velero.io/csi-volumesnapshot-class label, not by the default annotation. Missing it means Velero skips the volume and reports the backup as Completed"
}
output "write_test_data_command" {
  value       = local.outputs.write_test_data_command.value
  description = "Do this before the backup. Without it the volume is empty, and a restore producing an empty volume is indistinguishable from a restore that moved no data"
}
output "backup_command" {
  value       = local.outputs.backup_command.value
  description = "--snapshot-move-data matters more here than in the rehearsal: an EBS snapshot cannot be read from another account or region at all, so without it the replicated backup is metadata pointing at something the other side can never see"
}
output "list_backups_command" {
  value       = local.outputs.list_backups_command.value
  description = "Velero writes each backup under backups/<name>/. This is the source side; replication starts from here"
}
output "replication_status_command" {
  value       = local.outputs.replication_status_command.value
  description = "PENDING for a while is normal; FAILED means the destination bucket policy does not admit this role, the agreed role name does not match, or the destination bucket does not exist"
}
output "replication_metrics_command" {
  value       = local.outputs.replication_metrics_command.value
  description = "Failed replications over the last hour. Only published because Replication Time Control is on - with replication_time_minutes set to null these metrics do not exist"
}
output "restore_side_note" {
  value       = local.outputs.restore_side_note.value
  description = "The restore happens in the other account, from its own workbench, with its own credentials. Its Velero syncs the replicated backups out of its own bucket"
}
output "velero_log_command" {
  value       = local.outputs.velero_log_command.value
  description = "An AccessDenied here is the Pod Identity association; a NoSuchBucket is the BackupStorageLocation; a snapshot that never becomes ready is the snapshot-controller addon"
}
output "teardown_order" {
  value       = local.outputs.teardown_order.value
  description = "This root first, then the other one. The replication configuration has to go before the destination bucket. force_destroy is on here, so the destroy also deletes every backup and every version of every backup in this account's bucket"
}
output "update_kubeconfig_command" {
  value       = local.outputs.update_kubeconfig_command.value
  description = "User data already ran this. Re-run it if the kubeconfig is ever lost"
}
