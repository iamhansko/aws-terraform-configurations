output "bucket" {
  value       = aws_s3_bucket.s3_bucket.id
  description = "Name of the bucket"
}
output "bucket_arn" {
  value       = aws_s3_bucket.s3_bucket.arn
  description = "ARN of the bucket, for scoping another module's IAM policy to it"
}
output "bucket_regional_domain_name" {
  value       = aws_s3_bucket.s3_bucket.bucket_regional_domain_name
  description = "Regional domain name of the bucket, for use as a CloudFront origin"
}
