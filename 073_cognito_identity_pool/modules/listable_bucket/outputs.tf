output "bucket_name" {
  value       = aws_s3_bucket.bucket.id
  description = "Generated name of the bucket. The workshop page asks for it"
}
output "bucket_arn" {
  value       = aws_s3_bucket.bucket.arn
  description = "ARN of the bucket, which the identity pool's authenticated role may list"
}
output "prefixes" {
  value       = sort(distinct([for key in keys(var.sample_objects) : split("/", key)[0]]))
  description = "Top-level prefixes of the sample objects, which the workshop page asks for (rules.md B-5)"
}
