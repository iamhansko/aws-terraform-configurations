output "function_name" {
  value       = aws_lambda_function.function.function_name
  description = "Name of the function"
}
output "function_arn" {
  value       = aws_lambda_function.function.arn
  description = "ARN of the function"
}
output "execution_role_arn" {
  value       = aws_iam_role.execution.arn
  description = "ARN of the execution role"
}
output "log_group_name" {
  value       = aws_cloudwatch_log_group.function.name
  description = "Log group the function writes to"
}
output "invoke_command" {
  value       = "aws lambda invoke --function-name ${aws_lambda_function.function.function_name} --cli-binary-format raw-in-base64-out --payload '{}' /tmp/${aws_lambda_function.function.function_name}.json && cat /tmp/${aws_lambda_function.function.function_name}.json"
  description = "Invokes the function once and prints what it returned. statusCode 200 means the page was fetched and written; 500 carries the exception text in its body"
}
output "logs_command" {
  value       = "aws logs tail ${aws_cloudwatch_log_group.function.name} --since 15m"
  description = "The function's recent log output"
}
output "resolved_image_command" {
  value       = "aws lambda get-function --function-name ${aws_lambda_function.function.function_name} --query 'Code.[ImageUri,ResolvedImageUri]' --output text"
  description = "The tag the function was created from and the digest Lambda actually runs. The two diverge as soon as the tag is pushed over - which is why a push alone does not change what the function does"
}
output "update_code_command" {
  value       = "aws lambda update-function-code --function-name ${aws_lambda_function.function.function_name} --image-uri ${var.image_uri} > /dev/null && aws lambda wait function-updated --function-name ${aws_lambda_function.function.function_name}"
  description = "Re-resolves the tag to whatever digest it points at now, and waits for the update to finish. The step after a rebuild"
}
