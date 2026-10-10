output "trail_name" {
  value       = aws_cloudtrail.cloud_trail.name
  description = "Name of the trail"
}
output "trail_arn" {
  value       = aws_cloudtrail.cloud_trail.arn
  description = "ARN of the trail read from the resource. The bucket policy cannot use this - the trail depends on the policy - so it assembles the same ARN from the name instead"
}
output "logs_bucket_name" {
  value       = aws_s3_bucket.logs_bucket.id
  description = "Generated name of the log bucket"
}
output "logs_bucket_arn" {
  value       = aws_s3_bucket.logs_bucket.arn
  description = "ARN of the log bucket"
}
output "trail_status_command" {
  value       = "aws cloudtrail get-trail-status --name ${aws_cloudtrail.cloud_trail.name} --query '[IsLogging,LatestDeliveryTime,LatestDeliveryError]' --output table"
  description = "Command showing whether the trail is logging and delivering. The pipeline trigger depends on it entirely: IsLogging false, or a delivery error naming the bucket policy, means an upload to the source bucket starts nothing and the pipeline simply looks idle"
}
output "event_selector_command" {
  value       = "aws cloudtrail get-event-selectors --trail-name ${aws_cloudtrail.cloud_trail.name} --query 'EventSelectors[].[ReadWriteType,IncludeManagementEvents,DataResources]' --output json"
  description = "Command printing what the trail actually records. The data resource list is the part to check: management events alone never include an object PUT, so a trail without an object-level data resource leaves the EventBridge rule permanently silent"
}
