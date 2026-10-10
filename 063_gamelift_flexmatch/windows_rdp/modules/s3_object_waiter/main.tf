# Holds the apply until an object the Windows instance uploads is in S3: one function that polls for it, the
# role it runs as, and up to four synchronous invocations of it in a row.
#
# The game_artifacts_uploaded association's wait_for_success_timeout_seconds was supposed to do this and does
# not - an association no target has picked up yet reports Success at once, and that is the state every
# association created right after its instance is in (rules.md D-5; the root main.tf has the detail). The
# function asks S3 instead, which is the question the readers actually have.
#
# Copied from ../template's module of the same name and changed in one way (rules.md A-1): that workbench is
# done in about a minute, so one invocation of at most 900 seconds is plenty. This setup is given the PT30M the
# CloudFormation template's CreationPolicy allowed - Chocolatey, a 140 MB clone and the upload of all of it -
# and 900 seconds is the longest a Lambda function runs. So the wait is split into rounds.
locals {
  max_round_seconds = 900
  rounds            = ceil(var.timeout_seconds / local.max_round_seconds)
  # Spread evenly, so the rounds together take timeout_seconds rather than a multiple of 900.
  round_seconds = ceil(var.timeout_seconds / local.rounds)
  # round and rounds tell the handler whether it is the last round, which is the only one that fails on
  # running out of time.
  invocation_input = {
    bucket         = var.bucket_name
    key            = var.object_key
    association_id = var.association_id
    rounds         = local.rounds
  }
  # Every round's result, in order. The callers read the last one only: it exists only once every round has
  # returned, and the last round returns only with the object found. length() is known at plan, because the
  # counts below come from a variable.
  round_results = concat(
    [aws_lambda_invocation.round_1.result],
    aws_lambda_invocation.round_2[*].result,
    aws_lambda_invocation.round_3[*].result,
    aws_lambda_invocation.round_4[*].result,
  )
  final_result = jsondecode(local.round_results[length(local.round_results) - 1])
}
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
  timeout          = local.round_seconds
  filename         = data.archive_file.function.output_path
  source_code_hash = data.archive_file.function.output_base64sha256
  # The role's managed policy and the log group have to exist before the first invocation (rules.md D-1).
  depends_on = [aws_iam_role_policy_attachment.function, aws_cloudwatch_log_group.function]
}
# The wait itself, as up to four rounds. Each is synchronous, so the provider does not return until the
# function does, and each depends on the one before, so they run one after another rather than side by side -
# four parallel rounds would still end 900 seconds after they started. A round that runs out of time returns
# found = false and the next one carries on; once the object is there, every later round finds it at its first
# poll. Separate resources rather than one with count, because a count instance cannot depend on its sibling.
#
# They run once, when created, and again only when their input changes - a new bucket, key, association or
# number of rounds. A failed invocation is not recorded in state, so after a failure the next apply invokes
# that round again and the rounds before it stay as they were.
resource "aws_lambda_invocation" "round_1" {
  function_name = aws_lambda_function.function.function_name
  input         = jsonencode(merge(local.invocation_input, { round = 1 }))
  # The inline policy, not just the function: an invocation that races it gets 403 from S3. The handler
  # retries that, so a policy that is merely late costs a poll or two; one that is missing ends at the last
  # round's deadline with the 403 in the message (rules.md D-1).
  depends_on = [aws_iam_role_policy.function]
}
resource "aws_lambda_invocation" "round_2" {
  count = local.rounds >= 2 ? 1 : 0

  function_name = aws_lambda_function.function.function_name
  input         = jsonencode(merge(local.invocation_input, { round = 2 }))
  depends_on    = [aws_lambda_invocation.round_1]
}
resource "aws_lambda_invocation" "round_3" {
  count = local.rounds >= 3 ? 1 : 0

  function_name = aws_lambda_function.function.function_name
  input         = jsonencode(merge(local.invocation_input, { round = 3 }))
  depends_on    = [aws_lambda_invocation.round_2]
}
resource "aws_lambda_invocation" "round_4" {
  count = local.rounds >= 4 ? 1 : 0

  function_name = aws_lambda_function.function.function_name
  input         = jsonencode(merge(local.invocation_input, { round = 4 }))
  depends_on    = [aws_lambda_invocation.round_3]
}
