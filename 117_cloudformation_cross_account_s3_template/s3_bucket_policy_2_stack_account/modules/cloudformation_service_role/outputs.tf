output "role_arn" {
  value       = aws_iam_role.cloudformation.arn
  description = "ARN of the service role, which CreateStack takes as --role-arn"
}
output "role_name" {
  value       = aws_iam_role.cloudformation.name
  description = "Name of the service role"
}
output "policy_arns" {
  value       = sort(var.policy_arns)
  description = "What the role can do, re-exposed because it is the blast radius of every stack created with it (rules.md B-5)"
}
