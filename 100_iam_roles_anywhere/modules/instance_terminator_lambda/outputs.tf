output "function_name" {
  value       = aws_lambda_function.instance_terminator.function_name
  description = "Name of the function, which is also the suffix of its log group"
}
output "function_arn" {
  value       = aws_lambda_function.instance_terminator.arn
  description = "ARN of the function"
}
output "iam_role_arn" {
  value       = aws_iam_role.instance_terminator_lambda_iam_role.arn
  description = "ARN of the role the function runs as. It grants one EC2 action - see the policy comment in main.tf"
}
output "terminated_instances" {
  value       = jsondecode(aws_lambda_invocation.terminate_instances.result)
  description = "What the function verified and shut down, decoded from the invocation's return value: how long it waited, the LastModified of every object it waited for, and the instances it terminated. This is the one place the termination is visible to Terraform: the instance it killed is still recorded in state as running, because Terraform did not kill it. previous_state running with current_state shutting-down is the expected answer"
}
output "instance_ids" {
  value       = var.instance_ids
  description = "The instances that were handed to the invocation, returned so a caller comparing them against what was actually terminated is comparing against one definition (rules.md B-5)"
}
output "log_command" {
  value       = "aws logs tail /aws/lambda/${aws_lambda_function.instance_terminator.function_name} --since 1h"
  description = "The function's own log, which includes the event it was given - the handler prints it first. This is where a Runtime.HandlerNotFound or an UnauthorizedOperation shows up in full, rather than as the one line an apply prints"
}
