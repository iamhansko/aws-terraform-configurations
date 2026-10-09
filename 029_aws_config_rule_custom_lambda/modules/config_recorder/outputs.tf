output "bucket_name" {
  value       = aws_s3_bucket.config_bucket.id
  description = "Generated name of the delivery bucket"
}
output "bucket_arn" {
  value       = aws_s3_bucket.config_bucket.arn
  description = "ARN of the delivery bucket"
}
output "recorder_name" {
  value       = aws_config_configuration_recorder.config_recorder.name
  description = "Name of the configuration recorder, which every configservice command naming a recorder needs"
}
output "delivery_channel_name" {
  value       = aws_config_delivery_channel.delivery_channel.name
  description = "Name of the delivery channel"
}
output "service_role_arn" {
  value       = aws_iam_role.config_service_role.arn
  description = "ARN of the role AWS Config assumes"
}
output "service_role_name" {
  value       = aws_iam_role.config_service_role.name
  description = "Generated name of that role, so the caller can look up what is attached to it without finding it in the console first"
}
output "recorder_enabled" {
  value       = var.recorder_enabled
  description = "Whether the recorder was started, re-exposed so the caller's outputs can say what to expect from the status command rather than restating the input (rules.md B-5)"
}
output "recorder_status_command" {
  # Built here, where the recorder's name is, rather than assembled by the caller from an output and
  # a literal subcommand (rules.md B-5).
  value       = "aws configservice describe-configuration-recorder-status --region ${var.region} --configuration-recorder-names ${aws_config_configuration_recorder.config_recorder.name}"
  description = "Whether Config is actually recording. recording: true with lastStatus: SUCCESS is the working state. recording: false means the recorder exists but was never started, which produces no configuration items and therefore no evaluations. lastStatus: FAILURE with a message naming the bucket is the delivery permissions, not the rule"
}
output "snapshot_list_command" {
  value       = "aws s3 ls s3://${aws_s3_bucket.config_bucket.id}/AWSLogs/${var.account_id}/Config/ --recursive | tail -20"
  description = "What has actually been delivered. Empty for the first hour is normal - the snapshot frequency decides that - but empty combined with a FAILURE lastStatus is the bucket policy or the role's delivery policy"
}
