output "bucket_name" {
  value       = aws_s3_bucket.velero_backup_bucket.id
  description = "Name of the bucket. This is what Velero's backupStorageLocation wants - the name, not the ARN"
}
output "bucket_arn" {
  value       = aws_s3_bucket.velero_backup_bucket.arn
  description = "ARN of the bucket, for scoping the Velero role's object permissions to it rather than to every bucket in the account, which is what the _monolithic template's policy did"
}
output "bucket_region" {
  value       = aws_s3_bucket.velero_backup_bucket.region
  description = "Region the bucket is in, re-exposed so Velero's backupStorageLocation config reads the bucket's own region rather than whatever region the caller assumed (rules.md B-5). Getting this wrong makes every backup fail with a redirect error that names no bucket"
}
output "is_replication_destination" {
  value       = length(var.replication_source_role_arns) > 0
  description = "Whether a bucket policy was attached admitting another account's replication role. False on a bucket nothing replicates into"
}
output "list_backups_command" {
  value       = "aws s3 ls s3://${aws_s3_bucket.velero_backup_bucket.id}/backups/ --recursive --human-readable --summarize"
  description = "What is actually in the bucket. Velero writes each backup under backups/<name>/, so an empty listing after a backup reported Completed means the backup went to a different bucket - usually a backupStorageLocation pointing somewhere else"
}
output "list_incomplete_uploads_command" {
  value       = "aws s3api list-multipart-uploads --bucket ${aws_s3_bucket.velero_backup_bucket.id}"
  description = "Parts left by interrupted backups. These are billed and appear in no object listing, which is why the lifecycle rule exists - this is how to see whether it has anything to clean up yet"
}
