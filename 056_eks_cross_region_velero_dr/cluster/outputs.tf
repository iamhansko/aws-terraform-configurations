# Values are all projections of local.outputs in main.tf, so no expression is written twice and the
# README the SSM association writes cannot fall behind this file (rules.md B-5/H-2).
#
# description is the one thing that cannot come from the map: Terraform rejects an expression in an
# output's description with "Variables not allowed", so the wording exists literally in both places.
# The values do not.
output "vscode_url" {
  value       = local.outputs.vscode_url.value
  description = "Open the IDE here. Every command below is meant to be run from its terminal, where kubectl, helm, eksctl and the velero CLI are installed and both cluster contexts are already configured"
}
output "what_this_variant_is" {
  value       = local.outputs.what_this_variant_is.value
  description = "Two clusters in one account and one region, sharing a VPC and one backup bucket. The region boundary that gives the project its name is in the primary_account and secondary_account roots; this is the rehearsal, where everything except that boundary is real"
}
output "backup_bucket_name" {
  value       = local.outputs.backup_bucket_name.value
  description = "One bucket both Velero installations read and write. That shared bucket is what lets the secondary cluster see the primary's backups with no replication in between"
}
output "velero_status_command" {
  value       = local.outputs.velero_status_command.value
  description = "Run it for each context. The BackupStorageLocation must say Available: Unavailable means the plugin image is missing, the bucket region is wrong, or the Pod Identity association is not being used"
}
output "node_agent_check_command" {
  value       = local.outputs.node_agent_check_command.value
  description = "The node agent is what moves snapshot data into the bucket. Without it a backup taken with --snapshot-move-data puts nothing in the bucket and still reports Completed"
}
output "snapshot_class_check_command" {
  value       = local.outputs.snapshot_class_check_command.value
  description = "Velero picks a VolumeSnapshotClass by the velero.io/csi-volumesnapshot-class label, not by the default annotation. Missing it means Velero skips the volume and reports the backup as Completed"
}
output "workload_volume_check_command" {
  value       = local.outputs.workload_volume_check_command.value
  description = "One claim per pod, each Bound. A claim stuck Pending is the EBS CSI driver or a StorageClass name that does not exist"
}
output "write_test_data_command" {
  value       = local.outputs.write_test_data_command.value
  description = "Optional: the apply already wrote a line into every primary pod's index.html. This replaces pod 0's line with a fresh one before the backup, so a restore that moved no data is still distinguishable from one that did"
}
output "backup_command" {
  value       = local.outputs.backup_command.value
  description = "--snapshot-move-data is what puts the volume's contents in the bucket rather than leaving a region-local EBS snapshot. Not something the apply does: a backup is an act, not infrastructure"
}
output "backup_describe_command" {
  value       = local.outputs.backup_describe_command.value
  description = "Look at the item count and the data upload section. A backup that says Completed with zero volume snapshots is the EnableCSI feature or the snapshot class label"
}
output "list_backups_command" {
  value       = local.outputs.list_backups_command.value
  description = "Velero writes each backup under backups/<name>/. An empty listing after a backup reported Completed means it went to a different bucket"
}
output "restore_command" {
  value       = local.outputs.restore_command.value
  description = "Switch context first. The backup has to have synced into this cluster's Velero before it can be named, and the sync is a poll of the bucket rather than a push"
}
output "read_test_data_command" {
  value       = local.outputs.read_test_data_command.value
  description = "The same line written before the backup should come back here, from a volume this cluster built out of the backup. A StatefulSet with an empty volume means the objects were restored and the data was not"
}
output "restored_load_balancer_command" {
  value       = local.outputs.restored_load_balancer_command.value
  description = "The restore recreates the Service, and the secondary cluster's own controller builds a new NLB for it"
}
output "primary_owned_load_balancers_command" {
  value       = local.outputs.primary_owned_load_balancers_command.value
  description = "Run both. A load balancer tagged for the primary cluster while living in the secondary is the _monolithic template's bug - its second helm install passed the first cluster's name - and nothing else makes it visible"
}
output "velero_log_command" {
  value       = local.outputs.velero_log_command.value
  description = "An AccessDenied here is the Pod Identity association; a NoSuchBucket is the BackupStorageLocation; a snapshot that never becomes ready is the snapshot-controller addon"
}
output "teardown_note" {
  value       = local.outputs.teardown_note.value
  description = "force_destroy is on for the backup bucket, so terraform destroy deletes every backup and every version of every backup along with it. The EBS snapshots go too, because the VolumeSnapshotClass uses deletionPolicy Delete"
}
output "update_kubeconfig_command" {
  value       = local.outputs.update_kubeconfig_command.value
  description = "User data already set up both contexts, named primary and secondary. Re-run these if the kubeconfig is lost"
}
