output "name" {
  value       = aws_kinesis_firehose_delivery_stream.firehose.name
  description = "Name of the delivery stream. Read from the resource rather than echoing var.name, so it cannot disagree with what was created (rules.md B-5)"
}
output "arn" {
  value       = aws_kinesis_firehose_delivery_stream.firehose.arn
  description = "ARN of the delivery stream. The logging module scopes its firehose:PutRecordBatch permission to this"
}
output "bucket_name" {
  value       = aws_s3_bucket.destination.id
  description = "Generated name of the destination bucket. Generated rather than fixed because bucket names are globally unique"
}
output "role_arn" {
  value       = aws_iam_role.firehose_iam_role.arn
  description = "ARN of the role Firehose assumes to write to the bucket"
}
output "list_objects_command" {
  value       = "aws s3 ls s3://${aws_s3_bucket.destination.id}/ --recursive"
  description = "Command listing what Firehose has delivered. Objects are keyed by delivery time (YYYY/MM/DD/HH/), so an empty result within the first buffering interval is expected rather than a fault (rules.md H-2)"
}
output "read_latest_object_command" {
  value       = "aws s3 cp s3://${aws_s3_bucket.destination.id}/$(aws s3 ls s3://${aws_s3_bucket.destination.id}/ --recursive | sort | tail -1 | awk '{print $4}') -"
  description = "Command printing the most recently delivered object to stdout. Readable directly because compression_format is UNCOMPRESSED"
}
output "delivery_log_group_name" {
  value       = aws_cloudwatch_log_group.delivery.name
  description = "CloudWatch log group holding the delivery stream's own error records. Created by this module rather than left to the service, which only creates it when error logging is switched on through the console"
}
output "delivery_log_tail_command" {
  value       = "aws logs tail ${aws_cloudwatch_log_group.delivery.name} --since 15m"
  description = "Command printing the delivery stream's recent delivery errors. Empty output is the healthy case - this channel reports only failures, so it says nothing while records are being written successfully"
}
