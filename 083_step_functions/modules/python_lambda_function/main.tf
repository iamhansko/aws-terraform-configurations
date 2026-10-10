# One Python Lambda function, its role, and its log group.
#
# The three go together: a function with no log group gets one created for it on first invocation, with
# retention set to never expire, and a role that cannot write to that group produces a function that runs and
# logs nothing. The _monolithic template had the second problem solved by a managed policy and the first not
# solved at all.
data "archive_file" "source" {
  type = "zip"
  # source_dir rather than source_file, which is what the original used. A single file works until the
  # function gains a second one, and then the second one is silently missing from the package.
  source_dir  = var.source_dir
  output_path = "${path.module}/build/${var.name}.zip"
}
# Declared rather than left to Lambda. The name is not a choice - Lambda writes to exactly this path - so
# declaring it is the only way to set retention on it, and it also means terraform destroy removes the logs.
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
# An inline policy scoped to this function's own log group, rather than the AWSLambdaBasicExecutionRole
# managed policy the _monolithic template attached. That policy grants logs:CreateLogGroup and log writes
# across the account, which is more than a function needs and hides the fact that the log group is declared
# here.
resource "aws_iam_role_policy" "function" {
  name = "function"
  role = aws_iam_role.function.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [{
        Effect = "Allow"
        Action = ["logs:CreateLogStream", "logs:PutLogEvents"]
        # logs:CreateLogGroup is deliberately absent: the group is a declared resource, so a function that
        # needed to create it would be a sign the declaration and the function name had drifted apart.
        Resource = ["${aws_cloudwatch_log_group.function.arn}:*"]
      }],
      [for statement in var.additional_policy_statements : {
        Effect   = "Allow"
        Action   = statement.actions
        Resource = statement.resources
      }],
    )
  })
}
resource "aws_lambda_function" "function" {
  function_name    = var.name
  role             = aws_iam_role.function.arn
  runtime          = var.runtime
  handler          = var.handler
  timeout          = var.timeout
  memory_size      = var.memory_size
  filename         = data.archive_file.source.output_path
  source_code_hash = data.archive_file.source.output_base64sha256

  # Only when there is something to put in it. An empty environment block is a configuration difference
  # Lambda reports on every plan.
  dynamic "environment" {
    for_each = length(var.environment_variables) == 0 ? [] : [var.environment_variables]
    content {
      variables = environment.value
    }
  }

  logging_config {
    log_format = "JSON"
    log_group  = aws_cloudwatch_log_group.function.name
  }

  # role is an ARN reference, which orders this after the role but not after its policy (rules.md D-1). A
  # function invoked before the policy lands runs and writes no logs, which is a confusing first impression.
  depends_on = [aws_iam_role_policy.function, aws_cloudwatch_log_group.function]
}
