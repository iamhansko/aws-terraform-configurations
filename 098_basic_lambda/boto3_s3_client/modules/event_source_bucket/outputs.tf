output "bucket_name" {
  value       = aws_s3_bucket.event_source.id
  description = "Name of the bucket, read back off the resource rather than echoed from var.bucket_name, so a caller that mistypes the name sees the name S3 actually accepted"
}
output "bucket_arn" {
  value       = aws_s3_bucket.event_source.arn
  description = "ARN of the bucket. This is what the function's invoke permission narrows itself to, and taking it from here rather than assembling arn:aws:s3:::<name> is what keeps the permission and the bucket from drifting apart (rules.md B-5)"
}
output "versioning_status" {
  value       = aws_s3_bucket_versioning.event_source.versioning_configuration[0].status
  description = "Versioning state the bucket ended up in, re-exposed so the root can show it without restating the variable (rules.md B-5)"
}
output "upload_sample_command" {
  value       = <<-CMD
    printf '%s\n' '홍길동 hong.gildong@example.com 010-1234-5678' '주민번호 880101-1234567 카드 4111-1111-1111-1111' '식별자 3f2504e0-4f89-11d3-9a0c-0305e82c3301' > sample.txt && aws s3 cp sample.txt s3://${aws_s3_bucket.event_source.id}/${var.notification_filter_prefix == null ? "" : var.notification_filter_prefix}sample.txt
  CMD
  description = "Writes a sample file of the kinds of data the handler masks and uploads it under the prefix the notification filters on. The upload is what invokes the function - there is nothing else in this project that does"
}
output "list_masked_command" {
  value       = "aws s3 ls s3://${aws_s3_bucket.event_source.id}/${var.masked_object_prefix} --recursive"
  description = "What the function produced. Empty output after an upload means the function did not run or did not finish: check the log command before looking at the notification configuration, because a function that was invoked and failed leaves a log and no object"
}
output "diff_command" {
  value       = "aws s3 cp s3://${aws_s3_bucket.event_source.id}/${var.notification_filter_prefix == null ? "" : var.notification_filter_prefix}sample.txt - && echo '--- masked ---' && aws s3 cp s3://${aws_s3_bucket.event_source.id}/${var.masked_object_prefix}sample.txt -"
  description = "Prints the uploaded file and the masked copy one after the other, which is the actual result this project exists to show: surnames, email local parts, the last four digits of phone, identity and card numbers, and the final segment of a UUID all replaced with asterisks"
}
