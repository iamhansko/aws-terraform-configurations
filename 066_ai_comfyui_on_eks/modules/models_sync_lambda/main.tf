# The function that copies a newly uploaded model onto the GPU nodes that are already running.
#
# Replaces the blueprint's ComfyUI-on-EKS-Models stack (the Lambda half; the bucket is an s3_bucket instance in
# the root). The bucket notification that invokes this joins the bucket and the function, so it is declared in
# the root (rules.md C-1); the permission that lets S3 invoke it belongs to the function and lives here.
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}
data "archive_file" "source" {
  type        = "zip"
  source_dir  = var.source_dir
  output_path = "${path.module}/build/${var.function_name}.zip"
}
resource "aws_cloudwatch_log_group" "function" {
  name              = "/aws/lambda/${var.function_name}"
  retention_in_days = var.log_retention_days
}
resource "aws_iam_role" "function" {
  name_prefix = "${substr(var.function_name, 0, 32)}-"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}
# The blueprint's modelSync policy, narrowed to what the function calls.
#
# Its SendCommand condition named aws:eks:cluster-name, a tag Karpenter-launched instances never carry (see
# model_sync.py), so the condition allowed sending to none of the nodes the function looks for. It names
# eks:eks-cluster-name here. Two statements are dropped: ssm:GetCommandInvocation and the S3 read on the
# models bucket, neither of which the function's code ever calls - the copy runs on the node with the node
# role's credentials, not the function's. AWSLambdaBasicExecutionRole is replaced by write access to this
# function's own log group.
resource "aws_iam_role_policy" "function" {
  name = "model-sync"
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
        Action   = "ssm:SendCommand"
        Resource = "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:instance/*"
        Condition = {
          StringEquals = {
            "ssm:resourceTag/eks:eks-cluster-name" = var.cluster_name
          }
        }
      },
      {
        Effect   = "Allow"
        Action   = "ssm:SendCommand"
        Resource = "arn:${data.aws_partition.current.partition}:ssm:${data.aws_region.current.region}::document/AWS-RunShellScript"
      },
      {
        # DescribeInstances does not support resource-level permissions.
        Effect   = "Allow"
        Action   = "ec2:DescribeInstances"
        Resource = "*"
      },
    ]
  })
}
resource "aws_lambda_function" "function" {
  function_name    = var.function_name
  role             = aws_iam_role.function.arn
  runtime          = var.runtime
  handler          = "model_sync.lambda_handler"
  timeout          = var.timeout
  memory_size      = var.memory_size
  filename         = data.archive_file.source.output_path
  source_code_hash = data.archive_file.source.output_base64sha256

  environment {
    variables = {
      MODELS_BUCKET  = var.models_bucket_name
      NODE_DIR       = var.node_models_path
      CLUSTER_NAME   = var.cluster_name
      NODE_POOL_NAME = var.node_pool_name
    }
  }

  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.function.name
  }

  # The function's policy has to exist before the first invocation, and the role ARN does not imply the
  # inline policy (rules.md D-1).
  depends_on = [aws_iam_role_policy.function, aws_cloudwatch_log_group.function]
}
# Only the models bucket, from this account, may invoke the function.
resource "aws_lambda_permission" "allow_s3_invoke" {
  statement_id   = "AllowS3Invoke"
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.function.function_name
  principal      = "s3.amazonaws.com"
  source_arn     = var.models_bucket_arn
  source_account = data.aws_caller_identity.current.account_id
}
