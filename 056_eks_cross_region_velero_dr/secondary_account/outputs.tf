# Values are all projections of local.outputs in main.tf, so no expression is written twice and the
# README the SSM association writes cannot fall behind this file (rules.md B-5/H-2).
#
# description is the one thing that cannot come from the map: Terraform rejects an expression in an
# output's description with "Variables not allowed", so the wording exists literally in both places.
# The values do not.
output "apply_order" {
  value       = local.outputs.apply_order.value
  description = "This root goes first, before primary_account. Its replication configuration names this bucket, and S3 refuses a configuration whose destination does not exist"
}
output "vscode_url" {
  value       = local.outputs.vscode_url.value
  description = "Open the IDE here. The backup side is in the other account with its own workbench"
}
output "agreed_names" {
  value       = local.outputs.agreed_names.value
  description = "The only two things crossing the account boundary, and they cross as literal strings. primary_account's secondary_bucket_name must equal this bucket and its replication_role_name must equal the role this policy admits"
}
output "bucket_policy_check_command" {
  value       = local.outputs.bucket_policy_check_command.value
  description = "Compare the aws:PrincipalArn condition with the other account's replication_role_arn output. Principal should be that account's root ARN, and the condition narrows it to the agreed role"
}
output "velero_status_command" {
  value       = local.outputs.velero_status_command.value
  description = "The BackupStorageLocation must say Available. Velero here reads this account's bucket - it never talks to the other account at all"
}
output "storage_class_check_command" {
  value       = local.outputs.storage_class_check_command.value
  description = "A restored claim names its StorageClass, and Velero does not restore cluster-scoped StorageClasses from a namespaced backup - so the class has to be here before the restore"
}
output "list_replicated_backups_command" {
  value       = local.outputs.list_replicated_backups_command.value
  description = "An empty listing after the other account reported a completed backup means replication has not finished or has failed - that account's replication_status_command is where the reason is"
}
output "sync_check_command" {
  value       = local.outputs.sync_check_command.value
  description = "Velero finds backups by polling its BackupStorageLocation rather than being told, so a replicated backup appears here on the next sync rather than immediately"
}
output "restore_command" {
  value       = local.outputs.restore_command.value
  description = "This is the demonstration: the StatefulSet, its claims and the data in its volumes are all rebuilt here from objects that arrived in this account's bucket. Nothing in this configuration created the workload"
}
output "restore_describe_command" {
  value       = local.outputs.restore_describe_command.value
  description = "A restore that says Completed while the pods stay Pending is a storage class or a CSI driver problem, and both are things the restore cannot bring with it"
}
output "restored_volume_check_command" {
  value       = local.outputs.restored_volume_check_command.value
  description = "One claim per restored pod, each Bound. A claim stuck Pending means the data movement did not complete or the storage class is missing"
}
output "read_test_data_command" {
  value       = local.outputs.read_test_data_command.value
  description = "The line written on the other account's cluster before the backup should come back here, out of a volume this cluster built from objects that travelled through two buckets in two regions"
}
output "restored_load_balancer_command" {
  value       = local.outputs.restored_load_balancer_command.value
  description = "The restore recreates the Service and this account's own controller builds a new load balancer for it. The address differs from the original by necessity"
}
output "velero_log_command" {
  value       = local.outputs.velero_log_command.value
  description = "An AccessDenied here is the Pod Identity association; a NoSuchBucket is the BackupStorageLocation. A backup that never appears is replication rather than Velero, and that is diagnosed from the other account"
}
output "teardown_order" {
  value       = local.outputs.teardown_order.value
  description = "This root second, after primary_account. force_destroy is on here, so the destroy deletes every replicated backup - and those are the copies that were supposed to survive the primary region"
}
output "update_kubeconfig_command" {
  value       = local.outputs.update_kubeconfig_command.value
  description = "User data already ran this. Re-run it if the kubeconfig is ever lost"
}
