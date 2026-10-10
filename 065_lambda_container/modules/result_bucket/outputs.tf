output "bucket_name" {
  value       = aws_s3_bucket.bucket.id
  description = "Generated name of the bucket, handed to the function as BUCKET_NAME"
}
output "bucket_arn" {
  value       = aws_s3_bucket.bucket.arn
  description = "ARN of the bucket, so the function's role can be scoped to it rather than to every bucket in the account"
}
