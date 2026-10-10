output "bucket_name" {
  value       = aws_s3_bucket.artifact_bucket.id
  description = "Generated name of the artifact store bucket, which the pipeline's artifact_store block names"
}
output "bucket_arn" {
  value       = aws_s3_bucket.artifact_bucket.arn
  description = "ARN of the bucket. The CodeBuild and CodePipeline roles' S3 statements are scoped to this rather than to every bucket in the account, which is what the _monolithic template's s3:* on * was (rules.md A-5)"
}
output "artifact_list_command" {
  value       = "aws s3 ls s3://${aws_s3_bucket.artifact_bucket.id}/ --recursive --human-readable"
  description = "Command listing the artefacts the pipeline has produced. Empty after a run means the source stage never completed, which with this project's trigger chain usually means the archive was never uploaded"
}
