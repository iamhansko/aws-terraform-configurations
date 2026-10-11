output "function_name" {
  value       = aws_lambda_function.drain.function_name
  description = "Name of the drain function"
}
output "log_tail_command" {
  value       = "aws logs tail /aws/lambda/${aws_lambda_function.drain.function_name} --since 30m"
  description = "What the drain did on the last destroy. A TimeoutError here names how many instances were still registered"
}
