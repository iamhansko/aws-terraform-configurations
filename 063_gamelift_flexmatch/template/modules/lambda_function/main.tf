locals {
  vpc_attached = length(var.vpc_subnet_ids) > 0
  # Derived rather than passed in, so a VPC-attached function cannot be given the basic policy and fail
  # CreateFunction on ec2:CreateNetworkInterface. AWSLambdaVPCAccessExecutionRole carries the same three log
  # actions as the basic policy, so a VPC-attached function needs only the one. The _monolithic template gave
  # these functions AmazonVPCFullAccess, which is write access to every VPC resource in the account.
  execution_policy_arn = (local.vpc_attached
    ? "arn:${var.partition}:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
    : "arn:${var.partition}:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  )
}
resource "aws_iam_role" "function_role" {
  name_prefix = var.role_name_prefix
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = ["lambda.amazonaws.com"]
      }
      Action = ["sts:AssumeRole"]
    }]
  })
}
# toset is safe: the ARNs are built from a partition name and literals, all known at plan (rules.md B-7/B-8).
resource "aws_iam_role_policy_attachment" "function_role" {
  for_each   = toset(concat([local.execution_policy_arn], var.additional_policy_arns))
  role       = aws_iam_role.function_role.name
  policy_arn = each.value
}
resource "aws_iam_role_policy" "function_policy" {
  count = length(var.policy_statements) > 0 ? 1 : 0
  name  = "${var.function_name}-policy"
  role  = aws_iam_role.function_role.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [for statement in var.policy_statements : {
      Sid      = statement.sid
      Effect   = "Allow"
      Action   = statement.actions
      Resource = statement.resources
    }]
  })
}
resource "aws_lambda_function" "function" {
  function_name = var.function_name
  runtime       = var.runtime
  handler       = var.handler
  role          = aws_iam_role.function_role.arn
  timeout       = var.timeout
  memory_size   = var.memory_size
  s3_bucket     = var.s3_bucket
  s3_key        = var.s3_key
  dynamic "environment" {
    for_each = length(var.environment_variables) > 0 ? [1] : []
    content {
      variables = var.environment_variables
    }
  }
  dynamic "vpc_config" {
    for_each = local.vpc_attached ? [1] : []
    content {
      subnet_ids         = var.vpc_subnet_ids
      security_group_ids = var.vpc_security_group_ids
    }
  }
  # role names the role, not its policies. CreateFunction with a vpc_config checks for the ENI permissions on
  # the spot, and the event source mappings below are refused if the poll permissions are not there yet
  # (rules.md D-1).
  depends_on = [
    aws_iam_role_policy_attachment.function_role,
    aws_iam_role_policy.function_policy,
  ]
}
resource "aws_lambda_event_source_mapping" "event_source" {
  for_each          = var.event_source_mappings
  event_source_arn  = each.value.event_source_arn
  function_name     = aws_lambda_function.function.arn
  starting_position = each.value.starting_position
}
