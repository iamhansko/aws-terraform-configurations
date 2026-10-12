output "function_name" {
  value       = aws_lambda_function.function.function_name
  description = "Name of the function, which an invoke permission names"
}
output "function_arn" {
  value       = aws_lambda_function.function.arn
  description = "ARN of the function"
}
output "invoke_arn" {
  value       = aws_lambda_function.function.invoke_arn
  description = "ARN API Gateway calls the function through, for an integration or an authorizer"
}
output "role_name" {
  value       = aws_iam_role.function.name
  description = "Name of the function's execution role"
}
output "role_arn" {
  value       = aws_iam_role.function.arn
  description = "ARN of the function's execution role"
}
output "log_group_name" {
  value       = aws_cloudwatch_log_group.function.name
  description = "Log group the function writes to"
}
output "log_tail_command" {
  value       = "aws logs tail ${aws_cloudwatch_log_group.function.name} --follow --since 10m"
  description = "Follows the function's logs"
}
