output "function_name" {
  value       = aws_lambda_function.function.function_name
  description = "Name of the trigger function"
}
output "function_arn" {
  value       = aws_lambda_function.function.arn
  description = "ARN of the trigger function"
}
output "log_group_name" {
  value       = aws_cloudwatch_log_group.function.name
  description = "The function's log group. It holds the StartBuild response, which is where a permissions failure would appear"
}
output "started_build_id" {
  value       = var.start_build_on_apply ? jsondecode(aws_lambda_invocation.start_build[0].result).buildId : null
  description = "The build this apply started, or null with start_build_on_apply off. Read from the function's return value, which is why it returns one at all - the _monolithic template's version reported through cfn-response and returned nothing, so there was no way to find the build it had started (rules.md B-5)"
}
output "started_build_number" {
  value       = var.start_build_on_apply ? jsondecode(aws_lambda_invocation.start_build[0].result).buildNumber : null
  description = "Which build of the project this was. 1 on a first apply; a higher number means an earlier build already ran, and each build deploys the CDK stack again"
}
output "invoke_command" {
  value       = "aws lambda invoke --function-name ${aws_lambda_function.function.function_name} --payload '${jsonencode({ projectName = var.project_name })}' --cli-binary-format raw-in-base64-out /dev/stdout"
  description = "Starts a build through the function rather than directly, which is the way to check the function itself works - a permissions problem shows up here rather than in the build"
}
