# A Python function deployed from a source directory, with its execution role and its log group.
#
# What an AWS::Serverless::Function with an explicit Role expanded into under SAM, with the parts the
# _monolithic conversion dropped put back. That conversion pointed filename at the source directory itself
# ("./src"), which Lambda cannot take - it needs a zip - and it lost the template's Globals: the 480-second
# timeout, the 1024 MB of memory and every environment variable the code reads. The caller passes those here.
#
# The SAM templates' own policies were one inline document per function granting lambda:InvokeFunction, the
# logs actions and, where the code calls AWS, bedrock:*, translate:* and s3:* - all on "*". Here the logs
# actions come from AWSLambdaBasicExecutionRole and the rest are inline_policies, scoped by the caller to what
# the code calls.
data "archive_file" "function" {
  type        = "zip"
  source_dir  = var.source_dir
  output_path = "${path.module}/build/${var.function_name}.zip"
}
# The role SAM generates for a function: Lambda may assume it, and it carries AWSLambdaBasicExecutionRole.
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
resource "aws_iam_role_policy_attachment" "basic_execution" {
  role       = aws_iam_role.function.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
resource "aws_iam_role_policy" "inline" {
  for_each = var.inline_policies
  name     = each.key
  role     = aws_iam_role.function.id
  policy   = each.value
}
# Terraform's, so it is deleted with the function and has a retention. Under SAM - and in the _monolithic
# template - Lambda created it on the first invocation with no expiry, and deleting the stack left it behind.
resource "aws_cloudwatch_log_group" "function" {
  name              = "/aws/lambda/${var.function_name}"
  retention_in_days = var.log_retention_in_days
}
resource "aws_lambda_function" "function" {
  function_name    = var.function_name
  description      = var.description
  role             = aws_iam_role.function.arn
  filename         = data.archive_file.function.output_path
  source_code_hash = data.archive_file.function.output_base64sha256
  handler          = var.handler
  runtime          = var.runtime
  architectures    = [var.architecture]
  memory_size      = var.memory_size
  timeout          = var.timeout
  layers           = var.layers
  dynamic "environment" {
    for_each = length(var.environment) > 0 ? [var.environment] : []
    content {
      variables = environment.value
    }
  }
  # The role's policies and the log group have to exist before the first invocation (rules.md D-1).
  depends_on = [
    aws_iam_role_policy_attachment.basic_execution,
    aws_iam_role_policy.inline,
    aws_cloudwatch_log_group.function,
  ]
}
