output "layer_version_arn" {
  value       = aws_lambda_layer_version.layer.arn
  description = "ARN of the published layer version, which is what a function's layers list names"
}
output "version" {
  value       = aws_lambda_layer_version.layer.version
  description = "Version number of the published layer. It goes up each time the package's checksum changes"
}
output "package_bucket" {
  value       = aws_s3_bucket.package.id
  description = "Bucket the workbench uploads the layer package to"
}
output "package_bucket_arn" {
  value       = aws_s3_bucket.package.arn
  description = "ARN of the package bucket, which the caller's wait for the package is scoped to"
}
output "package_key" {
  value       = var.package_key
  description = "Key of the layer package in the package bucket, re-exposed so the upload and the lookup of its checksum name the same object (rules.md B-5)"
}
output "package_s3_uri" {
  value       = "s3://${aws_s3_bucket.package.id}/${var.package_key}"
  description = "Where the layer package was uploaded"
}
