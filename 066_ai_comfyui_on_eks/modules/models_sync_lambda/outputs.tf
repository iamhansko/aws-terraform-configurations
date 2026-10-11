output "function_name" {
  value       = aws_lambda_function.function.function_name
  description = "Name of the sync function"
}
output "function_arn" {
  value       = aws_lambda_function.function.arn
  description = "ARN of the sync function, for the bucket notification in the root"
}
output "permission_id" {
  value       = aws_lambda_permission.allow_s3_invoke.id
  description = "ID of the permission that lets the models bucket invoke the function. S3 rejects a notification configuration whose function it cannot invoke, so the root's notification has to come after this - referencing it is what orders the two (rules.md D-1)"
}
output "log_group_name" {
  value       = aws_cloudwatch_log_group.function.name
  description = "Log group the function writes to"
}
output "recent_logs_command" {
  value       = "aws logs tail ${aws_cloudwatch_log_group.function.name} --since 1h"
  description = "What the function did in the last hour: each model it saw, and which instances it sent the copy to"
}
