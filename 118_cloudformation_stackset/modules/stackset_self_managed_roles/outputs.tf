output "administration_role_arn" {
  value       = aws_iam_role.administration.arn
  description = "ARN of the administration role, which the StackSet names as administration_role_arn"
}
output "administration_role_name" {
  value       = aws_iam_role.administration.name
  description = "Name of the administration role"
}
output "execution_role_name" {
  value       = aws_iam_role.execution.name
  description = "Name of the execution role, which the StackSet names by name rather than by ARN - so every target account has to have a role called exactly this (rules.md B-5)"
}
output "execution_role_arn" {
  value       = aws_iam_role.execution.arn
  description = "ARN of the execution role in this account"
}
output "execution_role_policy_arns" {
  value       = sort(var.execution_role_policy_arns)
  description = "What the execution role can do, re-exposed because it is the blast radius of the whole StackSet and is not visible from the StackSet itself (rules.md B-5)"
}
output "permissions_ready" {
  value = concat(
    [for attachment in aws_iam_role_policy_attachment.execution : attachment.id],
    [for policy in aws_iam_role_policy.execution_inline : policy.id],
    [aws_iam_role_policy.administration_assume_execution.id],
  )
  description = "Handles on the policies rather than the roles, for a caller that needs to order the StackSet after the permissions exist. A role ARN reference orders against the role only, and a StackSet created before its administration role can assume anything fails on its first operation (rules.md D-1)"
}
