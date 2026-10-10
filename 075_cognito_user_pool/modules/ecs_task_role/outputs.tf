output "role_arn" {
  value       = aws_iam_role.task.arn
  description = "ARN of the task role"
}
output "policy_ready" {
  value       = aws_iam_role_policy.task.id
  description = "Handle on the role's policy, for a service that must not start tasks before the role can do anything. The role ARN alone orders against the role only (rules.md D-1)"
}
