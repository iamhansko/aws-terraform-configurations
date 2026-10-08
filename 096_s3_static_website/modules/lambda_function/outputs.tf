output "name" {
  value       = aws_lambda_function.function.function_name
  description = "Name of the function, which an aws lambda invoke call names"
}
output "arn" {
  value       = aws_lambda_function.function.arn
  description = "ARN of the function, which a caller scopes lambda:InvokeFunction to (rules.md B-5)"
}
output "role_arn" {
  value       = aws_iam_role.function.arn
  description = "ARN of the function's role"
}
output "role_name" {
  value       = aws_iam_role.function.name
  description = "Generated name of the role, for a caller attaching anything further to it"
}
output "log_group_name" {
  value       = aws_cloudwatch_log_group.function.name
  description = "The declared log group. Declared rather than left to Lambda, which would create it with retention set to never expire"
}
output "logs_command" {
  value       = "aws logs tail ${aws_cloudwatch_log_group.function.name} --since 15m --format short"
  description = "The function's recent output. For the backend this is the only way to see that an invocation happened at all, since the browser only reports whether the fetch succeeded"
}
output "function_url" {
  # one() rather than [0]. With create_function_url false the list is empty and [0] fails the plan with
  # "Invalid index"; one() returns null, which is what a caller that did not ask for a URL should see.
  value       = one(aws_lambda_function_url.function[*].function_url)
  description = "The public HTTP endpoint, or null when this function has no URL. The seeder writes this string into an object in the bucket so the page can fetch it, so it is load-bearing rather than informational - note it ends with a slash, which is what Lambda returns"
}
output "function_url_is_public" {
  value       = var.create_function_url && var.function_url_authorization_type == "NONE"
  description = "Whether the endpoint accepts unauthenticated requests. True for the backend by design - a browser has no credentials to sign with - and re-exposed because that is the one thing about this project that is not visible from the outside until someone else finds the URL (rules.md B-5)"
}
output "invoke_command" {
  value       = "aws lambda invoke --function-name ${aws_lambda_function.function.function_name} --cli-binary-format raw-in-base64-out --payload '{}' /dev/stdout"
  description = "Calls the function by hand. For the terminator this is how the instance is shut down when the automatic invocation is left off - the payload has to carry instance_ids, so see the root's terminate_seeder_command for the filled-in version"
}
