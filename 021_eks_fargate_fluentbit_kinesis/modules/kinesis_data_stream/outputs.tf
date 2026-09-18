output "name" {
  value       = aws_kinesis_stream.kinesis_data_stream.name
  description = "Name of the Kinesis data stream. Read from the resource rather than echoing var.name, so it cannot disagree with what was created (rules.md B-5)"
}
output "arn" {
  value       = aws_kinesis_stream.kinesis_data_stream.arn
  description = "ARN of the stream. The logging module scopes its kinesis:PutRecords permission to this, which is possible here and was not for CloudWatch log groups that Fluent Bit creates itself"
}
output "read_records_command" {
  value       = "aws kinesis get-records --shard-iterator $(aws kinesis get-shard-iterator --stream-name ${aws_kinesis_stream.kinesis_data_stream.name} --shard-id shardId-000000000000 --shard-iterator-type TRIM_HORIZON --query ShardIterator --output text) --query 'Records[].Data' --output text | base64 -d"
  description = "Command reading whatever Fluent Bit has written into the first shard. Records are base64 in the API response, hence the decode. An empty result usually means no pod has logged yet rather than a broken configuration (rules.md H-2)"
}
