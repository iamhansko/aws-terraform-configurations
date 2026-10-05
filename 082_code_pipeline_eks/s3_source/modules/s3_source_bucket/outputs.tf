output "bucket_name" {
  value       = aws_s3_bucket.source.id
  description = "Name of the bucket, which the pipeline's S3Bucket configuration, the EventBridge rule's pattern and the upload command all have to name (rules.md B-5)"
}
output "bucket_arn" {
  value       = aws_s3_bucket.source.arn
  description = "ARN of the bucket, so the pipeline role's bucket-level reads can be scoped to this one rather than to every bucket in the account (rules.md A-5)"
}
output "object_key" {
  value       = var.object_key
  description = "Key the pipeline reads, re-exposed so the source stage's configuration, the trigger's event pattern and the IAM statement all read one value rather than restating it (rules.md B-5)"
}
output "object_arn" {
  value       = "${aws_s3_bucket.source.arn}/${var.object_key}"
  description = "ARN of that one object, which is what the pipeline role's s3:GetObject is scoped to here - not the whole bucket, which is what the _monolithic template and AWS's own console-generated policy grant"
}
output "source_uri" {
  value       = "s3://${aws_s3_bucket.source.id}/${var.object_key}"
  description = "Where the archive goes. The workbench uploads here, and that upload is the pipeline's source event"
}
output "eventbridge_notifications_enabled" {
  value       = var.enable_eventbridge_notifications
  description = "Whether the bucket emits Object Created events, re-exposed because a rule matching events the bucket does not send is indistinguishable from a broken rule (rules.md B-5)"
}
output "upload_command" {
  value       = "cd ~/src && rm -f ~/${var.object_key} && zip -rq ~/${var.object_key} . && aws s3 cp ~/${var.object_key} s3://${aws_s3_bucket.source.id}/${var.object_key}"
  description = "Repackages the application and uploads it, which is the source event that starts a run. The archive is written outside the source directory, because writing it inside means the next run packs the previous archive into itself"
}
output "object_versions_command" {
  value       = "aws s3api list-object-versions --bucket ${aws_s3_bucket.source.id} --prefix ${var.object_key} --query 'Versions[].[LastModified,VersionId,IsLatest]' --output table"
  description = "Every version of the archive, which is the record of how many times the pipeline was triggered this way - and where the lifecycle rule's effect is visible"
}
