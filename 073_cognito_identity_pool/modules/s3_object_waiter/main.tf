# Holds the apply until an object that an SSM association uploads is in S3: one function that polls for it,
# the role it runs as, and one synchronous invocation of it.
#
# The association's wait_for_success_timeout_seconds was supposed to do this and does not - an association
# whose target has not registered with Systems Manager reports Success at once, and that is the state every
# association created right after its instance is in (rules.md D-5; the root main.tf has the timeline). The
# function asks S3 instead, which is the question the caller actually has. 100_iam_roles_anywhere moved the
# same wait into a function for the same reason.
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
# The calls the handler makes, each on the one resource it makes it on.
#
# ListBucket is there for HeadObject's sake, not for listing: without it S3 answers 403 rather than 404 for a
# key that does not exist yet, and the whole wait would read as a permissions failure. It cannot carry an
# s3:prefix condition for the same reason - HeadObject sends no prefix, so the condition would never match.
resource "aws_iam_role_policy" "function" {
  name = "wait-for-object"
  role = aws_iam_role.function.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadTheObject"
        Effect   = "Allow"
        Action   = "s3:GetObject"
        Resource = "${var.bucket_arn}/${var.object_key}"
      },
      {
        Sid      = "SeeThatItIsMissing"
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = var.bucket_arn
      },
      {
        Sid    = "SeeTheUploadFail"
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
# upload takes this shows "Still creating...", and whatever names the object through this result waits with it.
#
# It runs once, when it is created, and again only when its input changes - a new bucket, key or association,
# each of which means the object has to be uploaded afresh. A later upload to the same place (deploy.sh run by
# hand) needs no wait, because the object is already there. A failed invocation is not recorded in state, so
# the next apply invokes it again.
resource "aws_lambda_invocation" "wait" {
  function_name = aws_lambda_function.function.function_name
  input = jsonencode({
    bucket         = var.bucket_name
    key            = var.object_key
    association_id = var.association_id
  })

  # The inline policy, not just the function: an invocation that races it gets 403 from S3. The handler
  # retries that, so a policy that is merely late costs a poll or two; one that is missing ends at the timeout
  # with the 403 in the message (rules.md D-1).
  depends_on = [aws_iam_role_policy.function]
}
