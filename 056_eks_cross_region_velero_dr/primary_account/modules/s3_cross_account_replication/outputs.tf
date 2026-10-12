output "role_name" {
  value       = aws_iam_role.s3_replication.name
  description = "Name of the replication role, re-exposed so it can be compared against the name the other account's bucket policy was told (rules.md B-5/I-2). These two disagreeing is the most likely way this project fails, and the only symptom is objects whose replication status stays FAILED"
}
output "role_arn" {
  value       = aws_iam_role.s3_replication.arn
  description = "ARN of the replication role. This is the exact string the destination account's bucket policy has to name as its principal - print it and compare, because the other account assembled its copy from an account ID and an agreed name rather than from this value"
}
output "destination_bucket_name" {
  value       = var.destination_bucket_name
  description = "The bucket in the other account this replicates into, re-exposed so a mismatch with what that account actually created is visible in terraform output rather than only as an AccessDenied at apply time (rules.md B-5)"
}
output "replication_status_command" {
  value       = "aws s3api head-object --bucket ${var.source_bucket_name} --key <object-key> --query ReplicationStatus"
  description = "Whether one object replicated. PENDING for a while is normal; FAILED is the interesting case and means either the destination bucket policy does not admit this role, the role name the two accounts agreed on does not match, or the destination bucket does not exist"
}
output "replication_metrics_command" {
  value       = "aws cloudwatch get-metric-statistics --namespace AWS/S3 --metric-name OperationsFailedReplication --dimensions Name=SourceBucket,Value=${var.source_bucket_name} Name=DestinationBucket,Value=${var.destination_bucket_name} Name=RuleId,Value=${var.rule_id} --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ) --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) --period 300 --statistics Sum"
  description = "Failed replications over the last hour, which is the aggregate view head-object gives one object at a time. Only published because Replication Time Control is on - with replication_time_minutes set to null these metrics do not exist"
}
output "destination_listing_command" {
  value       = "aws s3 ls s3://${var.destination_bucket_name}/backups/ --recursive --human-readable --summarize"
  description = "What actually arrived in the other account's bucket. Run it with that account's credentials - this account's role can write there but cannot list it, which is a distinction that makes an empty result look like a replication failure when it is a permissions one"
}
