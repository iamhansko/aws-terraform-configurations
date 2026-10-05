# The function that starts the build, and the invocation that runs it.
#
# Both here because the invocation is the module's purpose: without it this is a function nobody calls. The
# _monolithic template had the same pair as a CloudFormation custom resource, and neither half could work -
# the code required cfn-response, which CloudFormation provides only to inline Lambda code, and read its
# arguments from event.ResourceProperties. lambda_src/trigger_function/index.mjs has the details.
data "archive_file" "source" {
  type        = "zip"
  source_dir  = var.source_dir
  output_path = "${path.module}/build/${var.name}.zip"
}
resource "aws_cloudwatch_log_group" "function" {
  name              = "/aws/lambda/${var.name}"
  retention_in_days = var.log_retention_days
}
resource "aws_iam_role" "function" {
  name_prefix = "${substr(var.name, 0, 32)}-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}
# An inline policy rather than the AWSLambdaBasicExecutionRole managed policy the _monolithic template
# attached alongside its own. That policy grants logs:CreateLogGroup and log writes across the account, which
# a function with a declared log group does not need.
resource "aws_iam_role_policy" "function" {
  name = "function"
  role = aws_iam_role.function.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = ["${aws_cloudwatch_log_group.function.arn}:*"]
      },
      {
        Effect   = "Allow"
        Action   = "codebuild:StartBuild"
        Resource = var.project_arn
      },
    ]
  })
}
resource "aws_lambda_function" "function" {
  function_name    = var.name
  role             = aws_iam_role.function.arn
  runtime          = var.runtime
  handler          = var.handler
  timeout          = var.timeout
  filename         = data.archive_file.source.output_path
  source_code_hash = data.archive_file.source.output_base64sha256

  logging_config {
    log_format = "JSON"
    log_group  = aws_cloudwatch_log_group.function.name
  }

  depends_on = [aws_iam_role_policy.function, aws_cloudwatch_log_group.function]
}
# aws_lambda_invocation rather than a null_resource with a local-exec: the call is made by the AWS provider
# with the same credentials as everything else, the returned build id lands in state, and a failure fails the
# apply.
#
# It re-invokes when its input changes. The input here is only the project name, so an ordinary second apply
# does not start a second build - which matters, because each build deploys a CDK stack.
resource "aws_lambda_invocation" "start_build" {
  count = var.start_build_on_apply ? 1 : 0

  function_name = aws_lambda_function.function.function_name
  input = jsonencode({
    projectName = var.project_name
  })

  # What makes this fire again. An aws_lambda_invocation is a one-shot: it re-invokes only when its
  # own arguments change, and its argument above is the project name, which does not change when the
  # thing being built does. So editing the Dockerfile or the buildspec produced a plan that updated
  # the CodeBuild project, applied cleanly, and started no build - the image in ECR stayed whatever
  # the last build had pushed, or stayed absent, and the only symptom was a workload pulling a stale
  # or missing tag.
  #
  # build_revision is a hash of the build definition, so a change to either becomes a change here and
  # a new build runs. Null leaves the map out entirely, which keeps the old behaviour for a caller
  # that does not pass it.
  triggers = var.build_revision == null ? null : {
    build_revision = var.build_revision
  }

  # The function's own policy has to exist before it is invoked, and a function ARN reference does not imply
  # that (rules.md D-1).
  depends_on = [aws_iam_role_policy.function]
}
