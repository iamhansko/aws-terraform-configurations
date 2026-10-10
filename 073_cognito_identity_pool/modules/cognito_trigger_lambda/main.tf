# The Lambda function behind a Cognito trigger, deployed by Terraform from the same source file the workshop
# copies onto the workbench.
#
# The _monolithic template deployed it from the workbench instead, as a SAM stack (cognito-lambdas), and then
# attached it to the pool with update-user-pool - which reset the pool's other settings (see the user pool
# module). Here the pool names this function's ARN and the attachment is part of the plan. The settings are
# the ones that SAM template's Globals gave it.
data "archive_file" "function" {
  type        = "zip"
  source_file = var.source_file
  output_path = "${path.module}/build/${var.function_name}.zip"
}
resource "aws_iam_role" "function" {
  name_prefix = "${substr(var.function_name, 0, 30)}-"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}
# for_each over literal ARNs known at plan (rules.md B-7). X-Ray because Tracing: Active was in the SAM
# Globals, which also attached this policy implicitly.
resource "aws_iam_role_policy_attachment" "function" {
  for_each = toset([
    "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole",
    "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess",
  ])
  role       = aws_iam_role.function.name
  policy_arn = each.value
}
# Terraform's, so it is deleted with the function rather than created by Lambda and left behind.
resource "aws_cloudwatch_log_group" "function" {
  name              = "/aws/lambda/${var.function_name}"
  retention_in_days = var.log_retention_in_days
}
resource "aws_lambda_function" "function" {
  function_name    = var.function_name
  runtime          = var.runtime
  handler          = var.handler
  role             = aws_iam_role.function.arn
  filename         = data.archive_file.function.output_path
  source_code_hash = data.archive_file.function.output_base64sha256
  memory_size      = 1024
  timeout          = 30
  architectures    = ["x86_64"]
  tracing_config {
    mode = "Active"
  }
  # The role's policies and the log group have to exist before the first invocation (rules.md D-1).
  depends_on = [aws_iam_role_policy_attachment.function, aws_cloudwatch_log_group.function]
}
