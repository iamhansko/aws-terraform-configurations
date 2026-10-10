output "bucket_name" {
  value       = aws_s3_bucket.game_source_bucket.id
  description = "Name of the bucket, for the uploads and for the resources that read from it"
}
output "bucket_arn" {
  value       = aws_s3_bucket.game_source_bucket.arn
  description = "ARN of the bucket, for policies scoped to its objects"
}
