output "function_arn" {
  value       = aws_lambda_function.function.arn
  description = "ARN of the function, which the user pool's trigger names"
}
output "function_name" {
  value       = aws_lambda_function.function.function_name
  description = "Name of the function, which the invoke permission names"
}
output "log_tail_command" {
  value       = "aws logs tail ${aws_cloudwatch_log_group.function.name} --follow --since 10m"
  description = "The trigger's output. It runs on every sign-in and token refresh"
}
