output "bucket_name" {
  value       = aws_s3_bucket.origin.id
  description = "Generated name of the origin bucket"
}
output "bucket_arn" {
  value       = aws_s3_bucket.origin.arn
  description = "ARN of the origin bucket"
}
output "distribution_id" {
  value       = aws_cloudfront_distribution.distribution.id
  description = "ID of the distribution"
}
output "domain_name" {
  value       = aws_cloudfront_distribution.distribution.domain_name
  description = "Domain name of the distribution"
}
output "url" {
  value       = "https://${aws_cloudfront_distribution.distribution.domain_name}"
  description = "URL of the distribution"
}
output "invalidate_command" {
  value       = "aws cloudfront create-invalidation --distribution-id ${aws_cloudfront_distribution.distribution.id} --paths '/*'"
  description = "Clears the edge caches. The bucket behaviour caches for a day, so a rebuilt client is not served until this runs"
}
