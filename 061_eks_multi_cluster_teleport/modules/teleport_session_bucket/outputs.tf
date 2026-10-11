output "bucket" {
  value       = aws_s3_bucket.teleport_session_bucket.id
  description = "Name of the session recording bucket, for the chart value and the IAM policy that grants access to it"
}
output "bucket_arn" {
  value       = aws_s3_bucket.teleport_session_bucket.arn
  description = "ARN of the bucket, for the resource element of the writer's IAM policy. Taken from the resource rather than rebuilt as arn:aws:s3:::<name>, so it stays correct in a partition where that prefix differs"
}
output "versioning_enabled" {
  value       = var.versioning_enabled
  description = "Whether versioning is on, re-exposed because Teleport rejects a session recording bucket without it at startup - and that rejection appears in a pod log rather than anywhere in Terraform (rules.md B-5)"
}
output "recording_list_command" {
  value       = "aws s3 ls s3://${aws_s3_bucket.teleport_session_bucket.id}/ --recursive --human-readable"
  description = "What has actually been recorded. Empty after a session has been replayed means Teleport is writing recordings somewhere else - usually because the bucket value never reached the chart"
}
output "configuration_check_command" {
  value       = "aws s3api get-bucket-versioning --bucket ${aws_s3_bucket.teleport_session_bucket.id} && aws s3api get-bucket-encryption --bucket ${aws_s3_bucket.teleport_session_bucket.id}"
  description = "The two properties Terraform sets here that the _monolithic template left to Teleport. Worth reading once after an apply, because a bucket that was configured by its consumer rather than by its owner looks the same from the console"
}
