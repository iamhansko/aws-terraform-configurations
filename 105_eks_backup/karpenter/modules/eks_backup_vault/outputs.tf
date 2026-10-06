output "vault_name" {
  value       = aws_backup_vault.vault.name
  description = "Name of the backup vault, which every backup and restore command needs"
}

output "vault_arn" {
  value       = aws_backup_vault.vault.arn
  description = "ARN of the backup vault"
}

output "backup_role_arn" {
  value       = aws_iam_role.backup.arn
  description = "ARN of the role AWS Backup assumes. Also the principal of the access entry the restore target cluster needs, which is why the caller reads it back (rules.md C-1)"
}

output "backup_role_name" {
  value       = aws_iam_role.backup.name
  description = "Name of the role AWS Backup assumes"
}

output "sns_topic_arn" {
  value       = aws_sns_topic.events.arn
  description = "Topic the vault's events are published to"
}

output "queue_url" {
  value       = aws_sqs_queue.events.id
  description = "URL of the queue subscribed to the topic. A URL rather than an ARN, which is what receive-message takes"
}

output "backup_plan_id" {
  value       = var.create_backup_plan ? aws_backup_plan.plan[0].id : null
  description = "Id of the backup plan, or null when no plan was created"
}

output "start_backup_command" {
  # Kept alongside the plan rather than instead of it. A scheduled plan is what makes the backup part of
  # the configuration; this is how the demo gets a recovery point without waiting for the next run.
  value       = "aws backup start-backup-job --backup-vault-name ${aws_backup_vault.vault.name} --iam-role-arn ${aws_iam_role.backup.arn} --resource-arn"
  description = "Starts a backup immediately. Append the resource ARN - normally the cluster's - because the plan's schedule may be hours away"
}

output "recovery_points_command" {
  value       = "aws backup list-recovery-points-by-backup-vault --backup-vault-name ${aws_backup_vault.vault.name} --query 'RecoveryPoints[].[RecoveryPointArn,Status,ResourceType]' --output table"
  description = "Every recovery point in the vault. An EKS backup produces a composite parent plus one child per attached volume, so a single cluster backup appears here as several rows"
}

output "skipped_objects_command" {
  value       = "aws sqs receive-message --queue-url ${aws_sqs_queue.events.id} --max-number-of-messages 10 --query 'Messages[].Body' --output text"
  description = "Reads the vault's notifications. This is where a restore that reported COMPLETED lists what it skipped - Services and Ingresses always, and anything whose CRD is missing on the target cluster"
}
