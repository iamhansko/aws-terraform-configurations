output "bucket" {
  value       = module.s3_bucket.bucket
  description = "Name of the bucket the source directory was synced into"
}

output "bucket_arn" {
  value       = module.s3_bucket.bucket_arn
  description = "ARN of the target bucket"
}

output "function_name" {
  value       = module.lambda_s3_sync.function_name
  description = "Name of the Lambda function that performed the sync"
}

output "log_group_name" {
  value       = module.lambda_s3_sync.log_group_name
  description = "CloudWatch log group holding the function's per-file sync output"
}

output "object_count" {
  value       = module.lambda_s3_sync.object_count
  description = "Number of files selected from the source directory"
}

output "object_keys" {
  value       = module.lambda_s3_sync.object_keys
  description = "Object keys the function was asked to sync, resolved at plan time from the local file tree"
}

output "sync_result" {
  value       = module.lambda_s3_sync.result
  description = "Decoded function result for the last invocation: which keys were uploaded, left unchanged, and deleted"
}

output "verify_command" {
  value       = "aws s3 ls s3://${module.s3_bucket.bucket}/${module.lambda_s3_sync.key_prefix} --recursive"
  description = "Command that lists what actually landed in the bucket, for confirming the recursive structure was preserved"
}
