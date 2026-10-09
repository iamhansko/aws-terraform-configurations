# The two roles a self-managed StackSet needs, and the trust between them.
#
# They are one module because they are one mechanism: CloudFormation assumes the administration role, that
# role assumes the execution role in each target account, and each half is useless without the other. The
# administration role's policy names the execution role by name, so splitting them would mean a caller
# restating that name in two places (rules.md C-2).
#
# permission_model SELF_MANAGED is what makes these necessary. The alternative, SERVICE_MANAGED, has
# CloudFormation create and manage its own roles through Organizations - fewer moving parts, but it requires
# the account to be an Organizations management account with trusted access enabled, which a demo cannot
# assume.
resource "aws_iam_role" "administration" {
  name        = var.administration_role_name
  description = var.administration_role_description

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "cloudformation.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}
# The administration role's only permission: assume the execution role, wherever it is.
#
# The wildcard in the account position is not laziness - it is how a StackSet reaches accounts that do not
# exist yet. The role name is fixed, which is what keeps it from being "assume anything anywhere".
resource "aws_iam_role_policy" "administration_assume_execution" {
  name = "AssumeRole-${var.execution_role_name}"
  role = aws_iam_role.administration.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "sts:AssumeRole"
      Resource = "arn:*:iam::*:role/${var.execution_role_name}"
    }]
  })
}
# The execution role. In a single-account StackSet this lives beside the administration role; in a
# multi-account one, a copy of it under the same name has to exist in every target account, created there by
# whatever means that account is managed - which is the part of self-managed StackSets that does not scale.
resource "aws_iam_role" "execution" {
  name        = var.execution_role_name
  description = "Assumed by ${var.administration_role_name} to create the StackSet's stacks in this account"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        # The account root form rather than the bare account id the _monolithic template used. Both work -
        # IAM normalises the bare id to this - but the ARN says what it means, and the two look different in
        # the console afterwards.
        AWS = [for id in var.trusted_administrator_account_ids : "arn:aws:iam::${id}:root"]
      }
      Action = "sts:AssumeRole"
    }]
  })
}
# for_each rather than one attachment resource per policy, so the list is the caller's to change without
# touching this module (rules.md B-7). The values are literal ARNs known at plan time, so toset is safe
# here - a list of ARNs coming from another module would have to be a map (rules.md B-8).
resource "aws_iam_role_policy_attachment" "execution" {
  for_each   = toset(var.execution_role_policy_arns)
  role       = aws_iam_role.execution.name
  policy_arn = each.value
}
resource "aws_iam_role_policy" "execution_inline" {
  count = length(var.execution_role_inline_policy_statements) == 0 ? 0 : 1
  name  = "stackset-execution"
  role  = aws_iam_role.execution.name

  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = var.execution_role_inline_policy_statements
  })
}
