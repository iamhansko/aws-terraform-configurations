output "bucket_name" {
  value       = aws_s3_bucket.website.id
  description = "Generated name of the bucket. The seeder instance is told this name rather than discovering it, so this is also what it writes into (rules.md B-6)"
}
output "bucket_arn" {
  value       = aws_s3_bucket.website.arn
  description = "ARN of the bucket, which the seeder's least-privilege write policy is scoped to (rules.md B-5)"
}
output "bucket_regional_domain_name" {
  value       = aws_s3_bucket.website.bucket_regional_domain_name
  description = "The bucket's REST endpoint hostname. Not what serves the site - it returns 404 for a request naming a directory - and exposed only so the difference from website_endpoint is visible"
}
output "website_endpoint" {
  value       = aws_s3_bucket_website_configuration.website.website_endpoint
  description = "The website endpoint's hostname. Taken from the website configuration resource rather than from aws_s3_bucket.website_endpoint, which the provider deprecated, and rather than assembled from the bucket name and region - the hostname's shape differs between the older regions (s3-website-<region>) and the newer ones (s3-website.<region>) and an assembled one that is wrong is a site that never resolves"
}
output "website_url" {
  value       = "http://${aws_s3_bucket_website_configuration.website.website_endpoint}"
  description = "The site. http, not https: an S3 website endpoint serves nothing else, which is the trade this project accepts and the thing 097_cloudfront_s3_static_website puts a distribution in front of to fix"
}
output "index_document" {
  value       = var.index_document
  description = "Re-exposed so a caller that has to put this key into the uploaded content uses the same value the website configuration serves, rather than restating it (rules.md B-5)"
}
output "error_document" {
  value       = var.error_document
  description = "Re-exposed for the same reason as index_document. Null means the endpoint returns its own XML page for a 4xx (rules.md B-5)"
}
output "list_objects_command" {
  value       = "aws s3 ls s3://${aws_s3_bucket.website.id}/ --recursive --human-readable"
  description = "What is actually in the bucket. Terraform uploads none of it - the seeder instance does - so this is the only way to tell a working site from a bucket the seeder failed to fill, and an empty listing here is the single most useful diagnostic this project has"
}
