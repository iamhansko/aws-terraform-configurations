output "delivery_stream_name" {
  value       = aws_kinesis_firehose_delivery_stream.delivery_stream.name
  description = "Name of the delivery stream"
}
output "delivery_stream_arn" {
  value       = aws_kinesis_firehose_delivery_stream.delivery_stream.arn
  description = "ARN of the delivery stream, which a CloudWatch Logs subscription filter names as its destination"
}
output "kms_key_arn" {
  value       = aws_kms_key.delivery_stream.arn
  description = "ARN of the key the stream encrypts its buffer with"
}
output "kms_alias_name" {
  value       = aws_kms_alias.delivery_stream.name
  description = "Alias of the stream's KMS key"
}
output "bucket_name" {
  value       = aws_s3_bucket.destination.id
  description = "Generated name of the destination bucket"
}
output "prefix" {
  value       = var.prefix
  description = "Key prefix delivered records land under, re-exposed so the root's listing command cannot drift from it (rules.md B-5)"
}
output "error_output_prefix" {
  value       = var.error_output_prefix
  description = "Key prefix failed records land under (rules.md B-5)"
}
output "buffering_interval_seconds" {
  value       = var.buffering_interval_seconds
  description = "How long a record waits in the buffer before it reaches S3, re-exposed because it is how long the demo takes to show anything (rules.md B-5)"
}
output "describe_command" {
  value       = "aws firehose describe-delivery-stream --delivery-stream-name ${aws_kinesis_firehose_delivery_stream.delivery_stream.name} --query 'DeliveryStreamDescription.[DeliveryStreamStatus,DeliveryStreamEncryptionConfiguration.Status,DeliveryStreamEncryptionConfiguration.KeyType]' --output table"
  description = "The stream's status and its encryption state. ENABLED with CUSTOMER_MANAGED_CMK is the property the _monolithic template lost in conversion"
}
output "list_delivered_command" {
  value       = "aws s3 ls s3://${aws_s3_bucket.destination.id}/${var.prefix} --recursive"
  description = "Objects delivered so far. Empty for the first buffering interval after traffic starts"
}
output "list_errors_command" {
  value       = "aws s3 ls s3://${aws_s3_bucket.destination.id}/${var.error_output_prefix} --recursive"
  description = "Records Firehose could not deliver. Anything here is the reason a gap appears in the delivered prefix"
}
