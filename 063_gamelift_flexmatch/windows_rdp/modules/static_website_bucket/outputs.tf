output "bucket_name" {
  value       = aws_s3_bucket.website.id
  description = "Generated name of the bucket, which the userdata uploads the leaderboard page into"
}
output "bucket_arn" {
  value       = aws_s3_bucket.website.arn
  description = "ARN of the bucket"
}
output "website_endpoint" {
  value       = aws_s3_bucket_website_configuration.website.website_endpoint
  description = "Website endpoint host name, without a scheme. Read from the website configuration rather than the bucket, whose website_endpoint attribute is deprecated in favour of this one"
}
output "website_url" {
  value       = "http://${aws_s3_bucket_website_configuration.website.website_endpoint}"
  description = "URL of the leaderboard page. http rather than https, because an S3 website endpoint does not serve TLS"
}
