# Scales the services to zero and waits for the managed instances to go, as the first step of terraform
# destroy.
#
# What this replaces is the _monolithic template's DeleteEcsManagedInstances custom resource, and the reason
# for it carries over unchanged: Terraform's own order would delete each service and then the capacity
# provider, but nothing makes it wait for ECS to actually terminate the instances in between. The services
# reference this invocation's input, so it is destroyed before them - which is exactly when the wait is
# needed.
data "archive_file" "drain" {
  type        = "zip"
  source_file = "${path.module}/lambda_src/drain/index.py"
  output_path = "${path.module}/build/drain.zip"
}
resource "aws_iam_role" "drain" {
  name_prefix = "${trimsuffix(substr(var.function_name, 0, 30), "-")}-"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}
# The two calls the handler makes, on the one cluster and the named services. The _monolithic template
# granted both on Resource "*", under a policy named AllowSecretManagerGetSecretValue - copied from the
# execution role's and never renamed.
resource "aws_iam_role_policy" "drain" {
  name = "DrainManagedInstances"
  role = aws_iam_role.drain.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ecs:DescribeClusters"]
        Resource = var.cluster_arn
      },
      {
        Effect   = "Allow"
        Action   = ["ecs:UpdateService"]
        Resource = var.service_arns
      },
    ]
  })
}
resource "aws_iam_role_policy_attachment" "drain_logs" {
  role       = aws_iam_role.drain.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
resource "aws_cloudwatch_log_group" "drain" {
  name              = "/aws/lambda/${var.function_name}"
  retention_in_days = var.log_retention_in_days
}
resource "aws_lambda_function" "drain" {
  function_name    = var.function_name
  runtime          = var.runtime
  handler          = "index.handler"
  role             = aws_iam_role.drain.arn
  timeout          = var.timeout_seconds
  filename         = data.archive_file.drain.output_path
  source_code_hash = data.archive_file.drain.output_base64sha256
  # The role's policies and the log group have to exist before the first invocation (rules.md D-1). On
  # destroy the order reverses, so the function is still able to call ECS when its delete-time run happens.
  depends_on = [
    aws_iam_role_policy.drain,
    aws_iam_role_policy_attachment.drain_logs,
    aws_cloudwatch_log_group.drain,
  ]
}
resource "aws_lambda_invocation" "drain" {
  function_name = aws_lambda_function.drain.function_name
  # CRUD rather than the default CREATE_ONLY. That is the whole point: it makes the provider invoke the
  # function again on destroy, with tf.action = "delete" in the event.
  lifecycle_scope = "CRUD"
  input = jsonencode({
    EcsCluster  = var.cluster_name
    EcsServices = var.service_names
  })
}
