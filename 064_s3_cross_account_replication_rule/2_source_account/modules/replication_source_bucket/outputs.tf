output "bucket_name" {
  value       = aws_s3_bucket.source.id
  description = "Generated name of the source bucket"
}
output "bucket_arn" {
  value       = aws_s3_bucket.source.arn
  description = "ARN of the source bucket"
}
output "rule_id" {
  value       = aws_s3_bucket_replication_configuration.source.rule[0].id
  description = "Id of the replication rule, which is what appears in each object's replication status and in the CloudWatch metrics"
}
output "replication_time_control_enabled" {
  value       = var.replication_time_minutes != null
  description = "Whether RTC is on, re-exposed because it is a billed feature and the difference is otherwise invisible - the rule looks the same either way (rules.md B-5)"
}
output "object_keys" {
  value       = sort(keys(aws_s3_object.demo))
  description = "Demo objects written into the source bucket. An empty list means nothing will appear in the destination and there is nothing to check, which is what the _monolithic template produced"
}
output "replication_status_command" {
  value       = length(var.objects) == 0 ? "aws s3api list-objects-v2 --bucket ${aws_s3_bucket.source.id} --query 'Contents[].Key' --output table" : "aws s3api head-object --bucket ${aws_s3_bucket.source.id} --key ${sort(keys(var.objects))[0]} --query 'ReplicationStatus' --output text"
  description = "The replication status S3 recorded on the first demo object, read from the source account. PENDING then COMPLETED is the normal path; FAILED means the role or the destination bucket policy is wrong, and it is the only place that failure is reported"
}
output "upload_command" {
  value       = "echo \"replicated at $(date -u +%FT%TZ)\" | aws s3 cp - s3://${aws_s3_bucket.source.id}/manual-test.txt"
  description = "Writes a fresh object, for watching replication happen rather than reading that it already did. Objects that existed before the rule was created are never replicated, so this is also how to test a rule added to an existing bucket"
}
