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
  description = "Key the template is stored under. Read from the object, so a caller referencing it is ordered after the upload (rules.md B-5)"
}
output "template_object_arn" {
  value       = "${aws_s3_bucket.templates.arn}/${aws_s3_object.template.key}"
  description = "ARN of the template object, for scoping a signer's s3:GetObject to exactly it"
}
