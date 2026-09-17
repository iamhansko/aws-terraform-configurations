output "bucket_name" {
  value       = aws_s3_bucket.s3_bucket.id
  description = "Name of the bucket, which a PersistentVolume using the Mountpoint S3 CSI driver passes as its bucketName volume attribute"
}
output "bucket_arn" {
  value       = aws_s3_bucket.s3_bucket.arn
  description = "ARN of the bucket, for the driver's IAM policy"
}
output "bucket_regional_domain_name" {
  value       = aws_s3_bucket.s3_bucket.bucket_regional_domain_name
  description = "Regional domain name of the bucket"
}
