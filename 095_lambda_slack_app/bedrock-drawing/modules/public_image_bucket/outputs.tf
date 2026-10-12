output "bucket_name" {
  value       = aws_s3_bucket.images.id
  description = "Name of the bucket, which the drawing function takes as TEXT_TO_IMAGE_S3_BUCKET_NAME"
}
output "bucket_arn" {
  value       = aws_s3_bucket.images.arn
  description = "ARN of the bucket, for scoping the function's write permission"
}
output "list_command" {
  value       = "aws s3 ls s3://${aws_s3_bucket.images.id}/"
  description = "Lists the generated images"
}
