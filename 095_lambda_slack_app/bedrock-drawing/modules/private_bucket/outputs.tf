output "bucket_name" {
  value       = aws_s3_bucket.bucket.id
  description = "Name of the bucket"
}
output "bucket_arn" {
  value       = aws_s3_bucket.bucket.arn
  description = "ARN of the bucket, for scoping the function's permissions"
}
