output "bucket_name" {
  value       = aws_s3_bucket.website.id
  description = "Generated name of the bucket"
}
output "bucket_arn" {
  value       = aws_s3_bucket.website.arn
  description = "ARN of the bucket"
}
output "website_endpoint" {
  value       = aws_s3_bucket_website_configuration.website.website_endpoint
  description = "The website endpoint's hostname, which is what the distribution uses as its origin. Taken from the website configuration resource rather than assembled from the bucket name and region, because the hostname's shape differs between the older regions (s3-website-<region>) and the newer ones (s3-website.<region>) and getting it wrong is an origin that never resolves"
}
output "index_document" {
  value       = var.index_document
  description = "Re-exposed so the distribution's default root object is the same key the website endpoint serves for a directory (rules.md B-5)"
}
output "requires_referer" {
  # nonsensitive, because sensitivity propagates through any expression that touches the value: the secret
  # comes from random_password, so even "is it null" is a sensitive boolean and a root output carrying it
  # fails with "Output refers to sensitive values". Whether a restriction exists leaks nothing - the secret
  # itself is never exposed anywhere.
  value       = nonsensitive(var.required_referer != null)
  description = "Whether the bucket policy requires the secret header. False means the objects are readable by anyone who knows the website endpoint, which makes the distribution bypassable - re-exposed because that is invisible from the outside (rules.md B-5)"
}
output "object_keys" {
  value       = sort(keys(aws_s3_object.content))
  description = "Objects written into the bucket. An empty list here explains a distribution that answers 404 to everything, which is what the _monolithic template produced"
}
output "direct_website_url" {
  value       = "http://${aws_s3_bucket_website_configuration.website.website_endpoint}"
  description = "The origin, reachable without going through CloudFront. Whether this answers is the test of whether the referer restriction is doing anything: with it on, this should return 403 while the distribution URL returns the page"
}
