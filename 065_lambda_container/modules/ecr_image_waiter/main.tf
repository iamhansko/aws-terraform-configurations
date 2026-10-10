# Holds the apply until the image the workbench pushes is in ECR: one function that polls for the tag, the role
# it runs as, and one synchronous invocation of it.
#
# The image_pushed association's wait_for_success_timeout_seconds was supposed to do this and does not - an
# association no target has picked up yet reports Success at once, and that is the state every association
# created right after its instance is in (rules.md D-5; the root main.tf has the timeline). The function asks
# ECR instead, which is the question CreateFunction actually has. Adapted from 063_gamelift_flexmatch's
# s3_object_waiter, which met the same failure on an S3 object (rules.md A-1).
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
  policy_arn = "arn:${var.partition}:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
# The calls the handler makes, each on the one resource it makes it on. DescribeImages needs no
# GetAuthorizationToken - that is for docker clients, and this function never pulls.
resource "aws_iam_role_policy" "function" {
  name = "wait-for-image"
  role = aws_iam_role.function.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "SeeTheImage"
        Effect   = "Allow"
        Action   = "ecr:DescribeImages"
        Resource = var.repository_arn
      },
      {
        Sid    = "SeeTheCheckFail"
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
# bootstrap and the push take this shows "Still creating...", and whatever is created from this result waits
# with it.
#
# It runs once, when it is created, and again only when its input changes - a new repository, tag or
# association. A later push to the same tag needs no wait, because the function already exists and the README's
# rebuild command updates it. A failed invocation is not recorded in state, so the next apply invokes it again.
resource "aws_lambda_invocation" "wait" {
  function_name = aws_lambda_function.function.function_name
  input = jsonencode({
    repository_name = var.repository_name
    image_tag       = var.image_tag
    image_uri       = var.image_uri
    association_id  = var.association_id
  })
  # The inline policy, not just the function: an invocation that races it gets AccessDenied from ECR. The
  # handler retries that, so a policy that is merely late costs a poll or two; one that is missing ends at the
  # timeout with the error in the message (rules.md D-1).
  depends_on = [aws_iam_role_policy.function]
}
