# The service role CloudFormation assumes to create, update and delete the stack's resources.
#
# What this role does not do is read the template: CloudFormation fetches a TemplateURL with the credentials
# of the CreateStack caller, so the bucket account's policy grants this account rather than this role.
resource "aws_iam_role" "cloudformation" {
  # A fixed name, as the _monolithic template had it. Nothing in the bucket account refers to it, so this is
  # not one of rules.md I-2's agreed names - it is fixed so the create-stack command is the same for everyone
  # who runs the demo.
  name        = var.name
  description = "Assumed by CloudFormation to manage the stack created from the bucket account's template"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "cloudformation.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}
# for_each over literal ARNs known at plan (rules.md B-7).
resource "aws_iam_role_policy_attachment" "cloudformation" {
  for_each   = toset(var.policy_arns)
  role       = aws_iam_role.cloudformation.name
  policy_arn = each.value
}
