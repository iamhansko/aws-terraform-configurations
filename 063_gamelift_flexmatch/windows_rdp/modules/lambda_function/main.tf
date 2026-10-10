# One game function: its execution role, the grants that role carries, the
# function, and whatever event sources invoke it by polling. The root
# instantiates this six times, all from the same Lambda/code.zip.
#
# Triggers that are push-based - API Gateway and SNS - are not here. Their
# permission belongs with the thing that invokes, so the API module and the
# topic module declare those; an event source mapping is the function's own
# polling configuration, so it stays with the function.
resource "aws_iam_role" "function" {
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
# for_each over the ARN list rather than one attachment per policy (rules.md
# B-7). toset is safe because managed policy ARNs are literals in configuration
# and known at plan time (rules.md B-8).
resource "aws_iam_role_policy_attachment" "managed" {
  for_each   = toset(concat(var.managed_policy_arns, var.additional_policy_arns))
  role       = aws_iam_role.function.name
  policy_arn = each.value
}
# The scoped grants, keyed by a label the caller chooses. A map because the
# documents name ARNs of resources other modules create, which are unknown at
# plan time; the keys are literals, so for_each can still address them
# (rules.md B-8).
resource "aws_iam_role_policy" "inline" {
  for_each = var.inline_policies
  name     = each.key
  role     = aws_iam_role.function.id
  policy   = each.value
}
resource "aws_lambda_function" "function" {
  function_name = var.function_name
  role          = aws_iam_role.function.arn
  runtime       = var.runtime
  handler       = var.handler
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
    for_each = length(var.subnet_ids) > 0 ? [1] : []
    content {
      subnet_ids         = var.subnet_ids
      security_group_ids = var.security_group_ids
    }
  }

  # CreateFunction with vpc_config is refused unless the role can already
  # create network interfaces, and that permission arrives with an attachment,
  # not with the role the function references (rules.md D-1).
  depends_on = [aws_iam_role_policy_attachment.managed, aws_iam_role_policy.inline]
}
resource "aws_lambda_event_source_mapping" "function" {
  for_each          = var.event_source_mappings
  function_name     = aws_lambda_function.function.arn
  event_source_arn  = each.value.event_source_arn
  starting_position = each.value.starting_position

  # CreateEventSourceMapping checks that the function's role can read the
  # source - ReceiveMessage on the queue, GetRecords on the stream - and fails
  # if the grant has not landed yet. The function reference orders this after
  # the function only (rules.md D-1).
  depends_on = [aws_iam_role_policy_attachment.managed, aws_iam_role_policy.inline]
}
