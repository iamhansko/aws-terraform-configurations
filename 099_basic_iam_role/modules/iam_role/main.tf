# One IAM role with one inline policy.
#
# The module deliberately knows nothing about how its two policy documents were written. That is the point
# of this project: the _monolithic template declared the same role three times, once with the policy as a
# YAML mapping, once as a JSON mapping and once as a JSON string, to show that CloudFormation flattens all
# three into the same document. The Terraform equivalent of that axis lives in the root - jsonencode of an
# HCL object, a policy document data source, and a heredoc literal - and this module is what proves they
# converge, by being the same code for all three (rules.md B-6).
resource "aws_iam_role" "role" {
  # Generated rather than fixed. CloudFormation generated these names, so the original had no name
  # collision to worry about; writing three literal names back in would make the project undeployable
  # twice in one account.
  name_prefix          = var.name_prefix
  description          = var.description
  max_session_duration = var.max_session_duration
  assume_role_policy   = var.assume_role_policy_json
}
resource "aws_iam_role_policy" "policy" {
  name   = var.inline_policy_name
  role   = aws_iam_role.role.name
  policy = var.inline_policy_json
}
