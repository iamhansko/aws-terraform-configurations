output "trail_name" {
  value       = aws_cloudtrail.cloud_trail.name
  description = "Name of the trail"
}
output "trail_arn" {
  value       = aws_cloudtrail.cloud_trail.arn
  description = "ARN of the trail"
}
output "logs_bucket_name" {
  value       = aws_s3_bucket.logs_bucket.id
  description = "Generated name of the trail log bucket"
}
output "trail_status_command" {
  value       = "aws cloudtrail get-trail-status --name ${aws_cloudtrail.cloud_trail.name} --query '[IsLogging,LatestDeliveryTime,LatestDeliveryError]' --output table"
  description = "Command showing whether the trail is logging and whether delivery is working. Worth checking first when an artefact upload does not start a pipeline: the EventBridge rules in this project depend entirely on this trail recording the write"
}
