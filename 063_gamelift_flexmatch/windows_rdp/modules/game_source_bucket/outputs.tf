output "bucket_name" {
  value       = aws_s3_bucket.game_source.id
  description = "Generated name of the bucket, which the userdata uploads to and the Lambda functions and GameLift build read from"
}
output "bucket_arn" {
  value       = aws_s3_bucket.game_source.arn
  description = "ARN of the bucket, for policies that grant read access to objects in it"
}
