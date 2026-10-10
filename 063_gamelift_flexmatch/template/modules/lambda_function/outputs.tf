output "function_name" {
  value       = aws_lambda_function.function.function_name
  description = "Name of the function"
}
output "function_arn" {
  value       = aws_lambda_function.function.arn
  description = "ARN of the function, for the SNS subscription"
}
output "invoke_arn" {
  value       = aws_lambda_function.function.invoke_arn
  description = "Invoke ARN of the function, which is the URI of an API Gateway AWS integration"
}
output "role_name" {
  value       = aws_iam_role.function_role.name
  description = "Name of the execution role, for attaching more policies from the root"
}
