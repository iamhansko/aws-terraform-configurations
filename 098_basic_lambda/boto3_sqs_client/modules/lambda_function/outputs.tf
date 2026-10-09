output "function_name" {
  value       = aws_lambda_function.function.function_name
  description = "Name of the function. The load generator resolves the URL from this name at runtime rather than being given the URL, so the two have to agree"
}
output "function_arn" {
  value       = aws_lambda_function.function.arn
  description = "ARN of the function"
}
output "function_url" {
  value       = aws_lambda_function_url.function.function_url
  description = "The HTTP endpoint. Public and unauthenticated while function_url_authorization_type is NONE, which is how the _monolithic template had it - a POST from anywhere puts a message on the queue"
}
output "authorization_type" {
  value       = aws_lambda_function_url.function.authorization_type
  description = "Whether the URL requires a signed request, read back off the resource. NONE means the invoke permission granting principal \"*\" exists; AWS_IAM means it does not (rules.md B-5)"
}
output "role_arn" {
  value       = aws_iam_role.function.arn
  description = "ARN of the execution role"
}
output "role_name" {
  value       = aws_iam_role.function.name
  description = "Name of the execution role, for attaching further policies from the root without this module changing"
}
output "queue_url" {
  value       = var.queue_url
  description = "The queue URL this function was configured to send to, handed straight back out (rules.md B-5). A function that returns 200 while the queue stays empty is this value pointing somewhere other than the queue the depth command is watching, and comparing the two outputs is how that is seen"
}
output "log_group_name" {
  value       = aws_cloudwatch_log_group.function.name
  description = "Log group the function writes to. Declared rather than created by Lambda on first use, so it has retention and destroy removes it"
}
output "invoke_command" {
  value       = <<-CMD
    curl -s -X POST ${aws_lambda_function_url.function.function_url} -H 'Content-Type: application/json' -d '{"message": "hello from terraform output"}'
  CMD
  description = "Sends one message by hand, which is the smallest end-to-end test of the whole project. Success prints the handler's literal \"Success\" body; a 403 means the invoke permission is missing or the URL needs signing, and a 500 means the handler reached the queue and was refused"
}
output "logs_command" {
  value       = "aws logs tail ${aws_cloudwatch_log_group.function.name} --since ${var.metrics_window_minutes}m --format short"
  description = "The function's own output. An empty group after a load run means the requests never arrived; a group full of KeyError means QUEUE_URL did not reach the environment"
}
output "throttle_metrics_command" {
  value       = <<-CMD
    for metric in Invocations Throttles Errors; do echo "== $metric"; aws cloudwatch get-metric-statistics --namespace AWS/Lambda --metric-name $metric --dimensions Name=FunctionName,Value=${aws_lambda_function.function.function_name} --start-time $(date -u -d '-${var.metrics_window_minutes} minutes' +%Y-%m-%dT%H:%M:%SZ) --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) --period 300 --statistics Sum --query 'Datapoints[].Sum' --output text; done
  CMD
  description = "Invocations, Throttles and Errors for the window, which is the measurement this project exists to produce and which no Terraform value can hold. Throttles are 429s: a function URL is a synchronous invoke, so every in-flight request holds one concurrent execution, and offering more simultaneous requests than the account's unreserved concurrency allows rejects the excess instantly rather than queueing it"
}
output "concurrency_metrics_command" {
  value       = <<-CMD
    aws cloudwatch get-metric-statistics --namespace AWS/Lambda --metric-name ConcurrentExecutions --dimensions Name=FunctionName,Value=${aws_lambda_function.function.function_name} --start-time $(date -u -d '-${var.metrics_window_minutes} minutes' +%Y-%m-%dT%H:%M:%SZ) --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) --period 60 --statistics Maximum --output table
  CMD
  description = "The ceiling the throttles came from. A Maximum that sits flat at one number for the whole run is the concurrency limit being hit, not the function being slow - raising memory_size moves neither"
}
