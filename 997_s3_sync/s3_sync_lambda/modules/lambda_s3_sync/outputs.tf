output "function_name" {
  value       = aws_lambda_function.lambda_function.function_name
  description = "Name of the Lambda function performing the sync"
}
output "function_arn" {
  value       = aws_lambda_function.lambda_function.arn
  description = "ARN of the Lambda function performing the sync"
}
output "role_arn" {
  value       = aws_iam_role.lambda_function_iam_role.arn
  description = "ARN of the function's execution role"
}
output "log_group_name" {
  value       = aws_cloudwatch_log_group.lambda_function.name
  description = "CloudWatch log group holding the function's per-file sync output"
}
output "source_dir" {
  value       = var.source_dir
  description = "Directory that was uploaded, re-exposed so callers reference one source of truth instead of holding the path independently"
}
output "key_prefix" {
  value       = var.key_prefix
  description = "Prefix every object key was written under, re-exposed for the same reason as source_dir"
}
output "object_keys" {
  value       = [for entry in local.objects : entry.key]
  description = "Object keys the invocation was asked to sync, known at plan time from the local file tree"
}
output "object_count" {
  value       = length(local.objects)
  description = "Number of files selected for upload"
}
output "result" {
  value       = jsondecode(aws_lambda_invocation.s3_sync.result)
  description = "Decoded function result: which keys were uploaded, left unchanged, and deleted on the last invocation"
}
