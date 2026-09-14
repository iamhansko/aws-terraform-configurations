output "bucket" {
  value       = module.s3_bucket.bucket
  description = "Name of the bucket the source directory was synced into"
}

output "bucket_arn" {
  value       = module.s3_bucket.bucket_arn
  description = "ARN of the target bucket"
}

output "object_count" {
  value       = module.s3_sync_local.object_count
  description = "Number of files selected from the source directory"
}

output "object_keys" {
  value       = module.s3_sync_local.object_keys
  description = "Object keys the sync is expected to produce, resolved at plan time from the local file tree"
}

output "sync_command" {
  value       = module.s3_sync_local.sync_command
  description = "The exact 'aws s3 sync' command that local-exec ran, for troubleshooting"
}

output "verify_command" {
  value       = "aws s3 ls s3://${module.s3_bucket.bucket}/${var.key_prefix} --recursive"
  description = "Command that lists what actually landed in the bucket, for confirming the recursive structure was preserved"
}
