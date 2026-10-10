output "task_role_arn" {
  value       = aws_iam_role.ecs_task_role.arn
  description = "ARN of the task role, named by all three task definitions. Assumed by the process inside the container - used at runtime by the product application's DynamoDB calls and by nothing else in this project"
}
output "task_role_name" {
  value       = aws_iam_role.ecs_task_role.name
  description = "Generated name of the task role, for attaching further policies from the root"
}
output "execution_role_arn" {
  value       = aws_iam_role.ecs_task_execution_role.arn
  description = "ARN of the task execution role, named by all three task definitions. Assumed by the ECS agent before a container starts: the ECR pull, the secret injection and the log stream"
}
output "execution_role_name" {
  value       = aws_iam_role.ecs_task_execution_role.name
  description = "Generated name of the task execution role"
}
output "task_role_policy_command" {
  value       = "aws iam list-role-policies --role-name ${aws_iam_role.ecs_task_role.name} --output text && aws iam list-attached-role-policies --role-name ${aws_iam_role.ecs_task_role.name} --output table"
  description = "What the task role can actually do, inline and attached. The point of reading it is to confirm what is not there: the _monolithic template gave this role AdministratorAccess, and what replaced it is one statement naming one table (rules.md A-5)"
}
