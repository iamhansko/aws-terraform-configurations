output "role_arn" {
  value       = aws_iam_role.replication.arn
  description = "ARN of the replication role, which the replication configuration names and which the destination bucket's policy in the other account has to trust. Not available until the role's policy exists - see depends_on"

  # The ARN exists as soon as the role does, and the policy is a separate resource, so a caller that only
  # references this value is ordered after the role and not after its permissions (rules.md D-1). The caller
  # here is the replication configuration, and the source bucket module writes the demo objects straight after
  # it: an object replicated before the policy lands records a FAILED status that S3 does not retry, which is
  # exactly the status the root's first output tells you to read. Holding the output back closes that.
  #
  # It does not create a cycle with the source bucket module, although that module consumes this ARN and the
  # policy consumes that module's bucket ARN: the graph is over resources, and the bucket resource depends on
  # neither.
  depends_on = [aws_iam_role_policy.replication]
}
output "role_name" {
  value       = aws_iam_role.replication.name
  description = "Name of the role, re-exposed so it can be compared against the replication_role_name the destination root was given - the two are the same literal string by agreement, and nothing checks that automatically (rules.md B-5/I-2)"
}
output "policy_name" {
  value       = aws_iam_role_policy.replication.name
  description = "Name of the inline policy"
}

