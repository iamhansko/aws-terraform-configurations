output "bucket_name" {
  value       = aws_s3_bucket.source_bucket.id
  description = "Generated name of the source bucket"
}
output "bucket_arn" {
  value       = aws_s3_bucket.source_bucket.arn
  description = "ARN of the source bucket, which the bastion's and the pipeline's S3 statements are scoped to rather than to every bucket in the account (rules.md A-5)"
}
output "object_key" {
  value       = var.object_key
  description = "The one key this bucket exists to hold, re-exposed so no reader restates it (rules.md B-5)"
}
output "object_arn" {
  value       = "${aws_s3_bucket.source_bucket.arn}/${var.object_key}"
  description = "Object-level ARN of that key, assembled here so the bucket and the key stay together. The CloudTrail data selector takes this rather than a bucket-level ARN: a bucket-level selector would record every write to the bucket and each one would start another pipeline run (rules.md B-5)"
}
output "versioning_status" {
  value       = aws_s3_bucket_versioning.source_bucket_versioning.versioning_configuration[0].status
  description = "Versioning state, exposed because CreatePipeline rejects a source bucket without it and because it is what makes force_destroy irreversible here"
}
output "object_check_command" {
  value       = "aws s3api head-object --bucket ${aws_s3_bucket.source_bucket.id} --key ${var.object_key} --query '[ContentLength,LastModified,VersionId]' --output text"
  description = "Whether the archive is actually there. A NoSuchKey here means the bastion's build never reached its upload, and in that case the pipeline's source stage has nothing to read and no S3 write ever happened for CloudTrail to record"
}
