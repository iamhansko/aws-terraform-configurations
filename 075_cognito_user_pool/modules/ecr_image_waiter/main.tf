# Holds the apply until the image tags an SSM association pushes are in ECR: one function that polls for them,
# the role it runs as, and one synchronous invocation of it.
#
# The association's wait_for_success_timeout_seconds was supposed to do this and does not. An association whose
# target has not registered with Systems Manager reports Success at once, which is the state an association
# created right after its instance is in; and an association updated in place - a new commit - is not waited on
# at all (rules.md D-5). The function asks ECR instead, which is the question the caller actually has.
# 073_cognito_identity_pool waits for its web app package the same way, and has the CloudTrail timeline of the
# first case.
data "archive_file" "function" {
  type        = "zip"
  source_file = "${path.module}/lambda_src/index.py"
  output_path = "${path.module}/build/${var.function_name}.zip"
}
resource "aws_iam_role" "function" {
  name_prefix = "${substr(var.function_name, 0, 37)}-"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}
resource "aws_iam_role_policy_attachment" "function" {
  role       = aws_iam_role.function.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
# The calls the handler makes, each on the resources it makes it on. DescribeImages answers
# ImageNotFoundException for a tag that is not there yet, so it needs nothing beside it to tell missing from
# forbidden.
resource "aws_iam_role_policy" "function" {
  name = "wait-for-images"
  role = aws_iam_role.function.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "SeeTheTags"
        Effect   = "Allow"
        Action   = "ecr:DescribeImages"
        Resource = distinct([for image in values(var.images) : image.repository_arn])
      },
      {
        Sid    = "SeeTheBuildFail"
        Effect = "Allow"
        Action = [
          "ssm:DescribeAssociation",
          "ssm:DescribeAssociationExecutions",
          "ssm:DescribeAssociationExecutionTargets",
        ]
        Resource = var.association_arn
      },
    ]
  })
}
# Terraform's, so it is deleted with the function rather than created by Lambda and left behind.
resource "aws_cloudwatch_log_group" "function" {
  name              = "/aws/lambda/${var.function_name}"
  retention_in_days = var.log_retention_in_days
}
resource "aws_lambda_function" "function" {
  function_name    = var.function_name
  role             = aws_iam_role.function.arn
  handler          = "index.lambda_handler"
  runtime          = var.runtime
  timeout          = var.timeout_seconds
  filename         = data.archive_file.function.output_path
  source_code_hash = data.archive_file.function.output_base64sha256
  # The role's managed policy and the log group have to exist before the first invocation (rules.md D-1).
  depends_on = [aws_iam_role_policy_attachment.function, aws_cloudwatch_log_group.function]
}
# The wait itself. Synchronous, so the provider does not return until the function does: for as long as the
# build takes this shows "Still creating...", and whatever names the images through this result waits with it.
#
# It runs when it is created and again whenever its input changes, which under the default CREATE_ONLY scope
# replaces it: a new tag (a new commit), a new repository or a new association - each a build whose images do
# not exist yet. The replacement is also what makes its result unknown at plan, so the lookups named through it
# wait again. A failed invocation is not recorded in state, so the next apply invokes it again.
resource "aws_lambda_invocation" "wait" {
  function_name = aws_lambda_function.function.function_name
  input = jsonencode({
    images = {
      for label, image in var.images : label => {
        repository_name = image.repository_name
        image_tag       = image.image_tag
      }
    }
    association_id = var.association_id
  })

  # The inline policy, not just the function: an invocation that races it gets AccessDenied from ECR. The
  # handler retries that, so a policy that is merely late costs a poll or two; one that is missing ends at the
  # timeout with the error in the message (rules.md D-1).
  depends_on = [aws_iam_role_policy.function]
}
