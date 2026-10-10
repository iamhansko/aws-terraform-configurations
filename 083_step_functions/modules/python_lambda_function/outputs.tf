output "name" {
  value       = aws_lambda_function.function.function_name
  description = "Name of the function"
}
output "arn" {
  value       = aws_lambda_function.function.arn
  description = "ARN of the function, which the state machine's task states name and which the caller scopes lambda:InvokeFunction to (rules.md B-5)"
}
output "role_arn" {
  value       = aws_iam_role.function.arn
  description = "ARN of the function's role"
}
output "role_name" {
  value       = aws_iam_role.function.name
  description = "Name of the role, for a caller attaching anything further to it"
}
output "log_group_name" {
  value       = aws_cloudwatch_log_group.function.name
  description = "The declared log group. Declared rather than left to Lambda, which would create it with retention set to never expire"
}
output "runtime" {
  value       = aws_lambda_function.function.runtime
  description = "Runtime the function is on, re-exposed so a deprecated one is visible in outputs rather than only in a console warning (rules.md B-5)"
}
output "logs_command" {
  value       = "aws logs tail ${aws_cloudwatch_log_group.function.name} --since 15m --format short"
  description = "The function's recent output. For the two data functions this shows what the state machine passed in, which is the quickest way to see why a Choice state went the way it did"
}
