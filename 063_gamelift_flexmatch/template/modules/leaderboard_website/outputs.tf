output "bucket_name" {
  value       = aws_s3_bucket.web_bucket.id
  description = "Name of the website bucket, which the client_config association uploads web/ into"
}
output "website_url" {
  value       = "http://${aws_s3_bucket_website_configuration.web_bucket_website.website_endpoint}"
  description = "URL of the leaderboard page. http rather than https because S3 website endpoints do not serve TLS"
}
