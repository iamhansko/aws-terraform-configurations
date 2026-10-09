output "function_name" {
  value       = aws_lambda_function.function.function_name
  description = "Name of the function, which the bucket notification in the root needs and which also fixes the log group path"
}
output "function_arn" {
  value       = aws_lambda_function.function.arn
  description = "ARN of the function. This is what the bucket notification points at, and it is the only value the root has to carry from this module to the bucket"
}
output "role_arn" {
  value       = aws_iam_role.function.arn
  description = "ARN of the function's execution role"
}
output "role_name" {
  value       = aws_iam_role.function.name
  description = "Name of the execution role, for attaching further policies from the root without this module changing"
}
output "source_bucket_arn" {
  value       = var.source_bucket_arn
  description = "The bucket ARN this function's invoke permission was narrowed to, handed straight back out (rules.md B-5). A notification that fires and a function that is never invoked is this value pointing at a different bucket than the one the notification was configured on, and that is visible by comparing this against the bucket output rather than by reading a policy in the console"
}
output "log_group_name" {
  value       = local.log_group_name
  description = "Log group Lambda writes to. It does not exist until the first invocation, so its absence is itself the answer to 'did anything invoke this function'"
}
output "logs_command" {
  value       = "aws logs tail ${local.log_group_name} --since ${var.log_tail_minutes}m --format short"
  description = "The function's own output. The handler prints the event it received and, on failure, the exception - so this distinguishes 'never invoked' (ResourceNotFoundException, no group) from 'invoked and failed' (a traceback) from 'invoked and skipped' (an event whose key was outside the filtered prefix)"
}
output "invocation_metrics_command" {
  value       = <<-CMD
    aws cloudwatch get-metric-statistics --namespace AWS/Lambda --metric-name Invocations --dimensions Name=FunctionName,Value=${aws_lambda_function.function.function_name} --start-time $(date -u -d '-${var.log_tail_minutes} minutes' +%Y-%m-%dT%H:%M:%SZ) --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) --period 300 --statistics Sum --output table
  CMD
  description = "How many times the function ran, which Terraform cannot know and no resource attribute reports. Swap Invocations for Errors to see how many of those failed; the two together are what tell you whether the notification is wired up but the handler is broken"
}
