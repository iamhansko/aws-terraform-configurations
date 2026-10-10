output "function_name" {
  value       = aws_lambda_function.function.function_name
  description = "Name of the function"
}
output "function_arn" {
  value       = aws_lambda_function.function.arn
  description = "ARN of the function, for an SNS subscription endpoint"
}
output "invoke_arn" {
  value       = aws_lambda_function.function.invoke_arn
  description = "API Gateway integration URI of the function"
}
output "role_arn" {
  value       = aws_iam_role.function.arn
  description = "ARN of the execution role"
}
output "role_name" {
  value       = aws_iam_role.function.name
  description = "Generated name of the execution role"
}
