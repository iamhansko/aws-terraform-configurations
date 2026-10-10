output "qualified_arns" {
  value       = { for key, f in aws_lambda_function.function : key => f.qualified_arn }
  description = "Qualified ARN (function:version) of each function's published version, keyed like the input map. This is what a distribution associates"
}
output "function_names" {
  value       = { for key, f in aws_lambda_function.function : key => f.function_name }
  description = "Name of each function"
}
output "versions" {
  value       = { for key, f in aws_lambda_function.function : key => f.version }
  description = "Published version number of each function"
}
output "log_group_names" {
  value       = { for key, f in aws_lambda_function.function : key => "/aws/lambda/us-east-1.${f.function_name}" }
  description = "Log group each function's replicas write to - one per region, in the region of the edge location that served the request, not in us-east-1"
}
