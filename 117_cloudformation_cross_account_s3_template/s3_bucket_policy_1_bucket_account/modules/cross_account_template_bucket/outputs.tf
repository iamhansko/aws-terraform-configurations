output "bucket_name" {
  value       = aws_s3_bucket.templates.id
  description = "Generated name of the template bucket"
}
output "bucket_arn" {
  value       = aws_s3_bucket.templates.arn
  description = "ARN of the template bucket"
}
output "template_key" {
  value       = aws_s3_object.template.key
  description = "Key the template is stored under (rules.md B-5)"
}
output "template_url" {
  # The regional virtual-hosted form, built here from the bucket's own region. The _monolithic stack account
  # template rebuilt this URL from the bucket name and its own region, which is a different URL as soon as
  # the two roots are applied in different regions.
  value       = "https://${aws_s3_bucket.templates.id}.s3.${data.aws_region.current.region}.amazonaws.com/${aws_s3_object.template.key}"
  description = "The URL the stack account passes to CreateStack as --template-url"
}
output "template_version_id" {
  value       = aws_s3_object.template.version_id
  description = "Version of the uploaded template object. Empty unless versioning is enabled on the bucket"
}
