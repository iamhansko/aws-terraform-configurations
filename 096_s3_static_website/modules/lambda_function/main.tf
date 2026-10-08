# One Python Lambda function, its role, its log group and optionally a public function URL.
#
# Instantiated twice by the root rather than written as two modules. The _monolithic template's two
# functions differ only in things that are naturally optional inputs here:
#
#   - the game backend has a function URL, a public invoke permission and one environment variable;
#   - the seeder terminator has an extra policy statement and no URL.
#
# Everything else is identical between them - python3.13, a 60 second timeout, a zip built by the archive
# provider, a role trusting lambda.amazonaws.com, and the basic execution permissions. Two modules would
# have meant two copies of the role, the log group, the attachment loop and the D-1 ordering below, and the
# only way to find out they had drifted apart would be noticing that one function logs and the other does
# not. The shape follows the reviewed module in 083_step_functions/modules/python_lambda_function
# (rules.md A-1 - copied, then evolved: that one has no function URL and builds its own zip).
#
# The function, the role and the log group stay together in one module for the reason 083 gives: a function
# with no declared log group gets one created on first invocation with retention set to never expire, and a
# role that cannot write to that group produces a function that runs and logs nothing. The _monolithic
# template had the second problem solved by a managed policy and the first not solved at all.
#
# The zip is not built here. data "archive_file" lives in the root, because every module in this root
# carries depends_on (rules.md D-3) and a module-level depends_on defers every data source inside that
# module to apply (rules.md D-6) - which would make filename and source_code_hash unknown at plan, so a
# changed index.py would stop being visible as a plan diff. The caller passes both in instead.

# Declared rather than left to Lambda. The name is not a choice - Lambda writes to exactly this path - so
# declaring it is the only way to set retention on it, and it also means terraform destroy removes the logs
# instead of leaving them billed forever.
resource "aws_cloudwatch_log_group" "function" {
  name              = "/aws/lambda/${var.name}"
  retention_in_days = var.log_retention_days
}
resource "aws_iam_role" "function" {
  # name_prefix, not name. The _monolithic template left both Lambda roles unnamed so CloudFormation
  # generated the names; a literal name here would be account-wide and would fail the second apply in one
  # account with EntityAlreadyExists.
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
# An inline policy scoped to this function's own log group, plus whatever the caller says the function
# calls.
#
# The _monolithic template attached arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole to
# both Lambda roles. That policy grants logs:CreateLogGroup and log writes across the whole account, which
# is more than either function needs and hides the fact that the log group is a declared resource here. It
# is still reachable - managed_policy_arns takes it - but the default is the narrow version, which follows
# the direction rules.md A-5 sets: a conversion may narrow an automated role's permissions and say why, and
# must never widen them.
resource "aws_iam_role_policy" "function" {
  name = var.inline_policy_name
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
      var.additional_policy_statements,
    )
  })
}
# for_each over the policy list rather than one attachment resource per policy, so a caller can add or
# remove a managed policy without this module changing (rules.md B-7). toset is safe because these ARNs are
# literal strings in configuration and are therefore known at plan time; a list of ids coming out of
# another module would have to arrive as a map with static keys instead (rules.md B-8).
resource "aws_iam_role_policy_attachment" "function" {
  for_each   = toset(var.managed_policy_arns)
  role       = aws_iam_role.function.name
  policy_arn = each.value
}
resource "aws_lambda_function" "function" {
  function_name    = var.name
  role             = aws_iam_role.function.arn
  runtime          = var.runtime
  handler          = var.handler
  timeout          = var.timeout
  memory_size      = var.memory_size
  filename         = var.filename
  source_code_hash = var.source_code_hash

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

  # role is an ARN reference, which orders this after the role but not after the policy on it or the log
  # group it writes to (rules.md D-1). A function created and invoked before the inline policy lands runs
  # and writes nothing, so the first thing anyone does to diagnose it - read the logs - finds an empty log
  # group and no explanation.
  depends_on = [aws_iam_role_policy.function, aws_cloudwatch_log_group.function]
}
# The public HTTP endpoint for the backend. Optional, because only one of the two functions has one.
#
# Security, stated plainly rather than left to be discovered: with authorization_type NONE this is an
# unauthenticated endpoint on the public internet, and in this project it returns the escape-room password
# to any caller. That is the game's design - the browser fetches it with no credentials to send - and it is
# the same exposure the bucket policy already has. It is not a pattern to copy into anything that is not
# deliberately public. AWS_IAM is the alternative and requires every caller to sign the request, which the
# game cannot do.
resource "aws_lambda_function_url" "function" {
  count = var.create_function_url ? 1 : 0

  function_name      = aws_lambda_function.function.function_name
  authorization_type = var.function_url_authorization_type
  invoke_mode        = var.function_url_invoke_mode

  dynamic "cors" {
    for_each = length(var.function_url_allow_origins) == 0 ? [] : [var.function_url_allow_origins]
    content {
      allow_origins = cors.value
    }
  }
}
# Without this the function URL exists and returns 403 to everyone.
#
# Creating a function URL with authorization_type NONE through the console adds this resource policy
# statement for you; creating one through the API, which is what Terraform does, does not. The
# _monolithic template had the permission, and its action was spelled lambda:invokeFunctionUrl - IAM
# compares action names case-insensitively so it worked, but the canonical spelling is used here.
#
# Not created when the URL requires AWS_IAM: a "*" principal with no auth type condition would then be
# a genuinely open door rather than the intended one.
resource "aws_lambda_permission" "function_url" {
  count = var.create_function_url && var.function_url_authorization_type == "NONE" ? 1 : 0

  statement_id           = "AllowPublicFunctionUrlInvoke"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.function.function_name
  principal              = "*"
  function_url_auth_type = "NONE"
}
