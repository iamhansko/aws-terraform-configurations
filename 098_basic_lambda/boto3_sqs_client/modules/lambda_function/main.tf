# The front door of the project: a function URL that takes an HTTP POST and turns its body into one SQS
# message. Function, role, queue permission, URL and the public invoke permission are one module because none
# of them is useful alone - a URL without the invoke permission answers 403 to everyone, and a function
# without the inline queue statement answers 500 for every request.
#
# source_dir rather than the conversion's source_file: a single named file works until the handler grows a
# second one, and then the second one is silently absent from the package and every invocation fails with
# ModuleNotFoundError for a file that is sitting next to index.py in the repository.
data "archive_file" "source" {
  type        = "zip"
  source_dir  = var.source_directory
  output_path = "${path.module}/build/${var.function_name}.zip"
}
# Declared rather than left to Lambda, so retention applies and destroy cleans up. The name is not a choice:
# the runtime writes to exactly this path, which is also why the function below waits for it (see the
# log_retention_days description for the ResourceAlreadyExistsException this ordering avoids).
resource "aws_cloudwatch_log_group" "function" {
  name              = "/aws/lambda/${var.function_name}"
  retention_in_days = var.log_retention_days
}
resource "aws_iam_role" "function" {
  name        = var.role_name
  name_prefix = var.role_name == null ? "queue-lambda-" : null

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        # A list of one, as the conversion rendered CloudFormation's single-element Service array. IAM
        # normalises it to a plain string, so leaving it as a list means every plan after the first shows no
        # difference while the console shows the scalar form - harmless, and the reason it is spelled as a
        # scalar here.
        Service = "lambda.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}
# The one piece of least privilege the original already had: SendMessage on this queue and nothing else. The
# ARN arrives as a variable because the queue belongs to another module (rules.md B-6), and it is an ARN
# rather than the URL because an IAM Resource element cannot be a URL.
resource "aws_iam_role_policy" "queue_access" {
  name = "SQSAccess"
  role = aws_iam_role.function.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["sqs:SendMessage"]
      Resource = var.queue_arn
    }]
  })
}
# One for_each rather than one resource per policy (rules.md B-7). toset is correct here because these ARNs
# are literal strings in configuration and so are known at plan time; the same expression over IDs coming out
# of another module fails with "Invalid for_each argument" and has to become a map with static keys
# (rules.md B-8), which is exactly what the worker instance's security group sources do.
resource "aws_iam_role_policy_attachment" "function" {
  for_each   = toset(var.iam_policy_arns)
  role       = aws_iam_role.function.name
  policy_arn = each.value
}
resource "aws_lambda_function" "function" {
  function_name    = var.function_name
  role             = aws_iam_role.function.arn
  runtime          = var.runtime
  handler          = var.handler
  timeout          = var.timeout
  memory_size      = var.memory_size
  filename         = data.archive_file.source.output_path
  source_code_hash = data.archive_file.source.output_base64sha256

  environment {
    variables = {
      # The handler reads this with os.environ['QUEUE_URL'] - a subscript, not a .get - so a missing variable
      # is a KeyError raised while the module is being imported. Every invocation then fails before the
      # handler runs, and the error says nothing about configuration.
      QUEUE_URL = var.queue_url
    }
  }

  # role is an ARN reference, which orders this after the role and after nothing attached to it (rules.md
  # D-1). The window is real and its symptom is confusing: a function invoked before the inline policy lands
  # returns 500 with an AccessDenied on sqs:SendMessage, which reads as a broken queue rather than as a race
  # that will not happen again.
  depends_on = [
    aws_iam_role_policy.queue_access,
    aws_iam_role_policy_attachment.function,
    aws_cloudwatch_log_group.function,
  ]
}
resource "aws_lambda_function_url" "function" {
  function_name      = aws_lambda_function.function.function_name
  authorization_type = var.function_url_authorization_type
}
# What makes an unauthenticated function URL actually callable. With authorization_type NONE, Lambda still
# requires a resource policy granting lambda:InvokeFunctionUrl, and principal "*" is the only principal that
# expresses "anyone" - so this statement is the public exposure, not the URL itself.
#
# count ties it to the authorization type instead of leaving it unconditional. Switching
# function_url_authorization_type to AWS_IAM with this statement still in place would leave a policy granting
# the world an action the URL no longer accepts unsigned: not exploitable, but it reads like the endpoint is
# still open, and a reader auditing the account would have to work out which of the two settings wins.
resource "aws_lambda_permission" "function_url" {
  count = var.function_url_authorization_type == "NONE" ? 1 : 0

  function_name          = aws_lambda_function.function.function_name
  action                 = "lambda:InvokeFunctionUrl"
  principal              = "*"
  function_url_auth_type = "NONE"
}
