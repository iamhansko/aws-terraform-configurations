output "name" {
  value       = aws_iam_role.role.name
  description = "Generated name of the role"
}
output "arn" {
  value       = aws_iam_role.role.arn
  description = "ARN of the role"
}
output "unique_id" {
  value       = aws_iam_role.role.unique_id
  description = "The role's AROA identifier. Worth having next to the ARN: this is what appears in CloudTrail and in a resource policy's principal after the role has been deleted and recreated under the same name, which is how a stale trust relationship shows itself"
}
output "assume_role_policy" {
  value       = aws_iam_role.role.assume_role_policy
  description = "The trust policy as IAM stored it, rather than as it was written. This is what makes the project's point visible: three roles whose documents were authored three different ways come back from IAM identical (rules.md B-5)"
}
output "inline_policy_name" {
  value       = aws_iam_role_policy.policy.name
  description = "Name of the inline policy, re-exposed so the caller's read command names the same string it passed in (rules.md B-5)"
}
output "read_policies_command" {
  value       = "aws iam get-role --role-name ${aws_iam_role.role.name} --query 'Role.AssumeRolePolicyDocument' --output json && aws iam get-role-policy --role-name ${aws_iam_role.role.name} --policy-name ${aws_iam_role_policy.policy.name} --query 'PolicyDocument' --output json"
  description = "Both documents as IAM holds them. Run it for each of the three roles and compare: identical output is the whole lesson, and it is not visible from the configuration, where the three are written differently on purpose"
}
