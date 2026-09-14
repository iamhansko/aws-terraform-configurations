output "bucket" {
  value       = aws_s3_bucket.s3_bucket.id
  description = "Name of the bucket"
}

output "bucket_arn" {
  value       = aws_s3_bucket.s3_bucket.arn
  description = "ARN of the bucket"
}
