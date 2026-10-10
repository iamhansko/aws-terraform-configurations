# The Lambda@Edge functions, one published version each, and the role they share.
#
# This module is called with an aws provider configured for us-east-1 (rules.md I-3). Lambda@Edge accepts
# only functions created there - CloudFront replicates them from us-east-1 to its edge locations - and the
# _monolithic template created them through the stack's single provider. Applied anywhere but us-east-1, its
# distribution failed at apply with "The function must be in region 'us-east-1'".
resource "aws_iam_role" "lambda_edge" {
  name_prefix = "${var.name_prefix}-edge-"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      # edgelambda as well as lambda: the replicas at the edge are run by the Lambda@Edge service principal.
      Principal = { Service = ["lambda.amazonaws.com", "edgelambda.amazonaws.com"] }
      Action    = "sts:AssumeRole"
    }]
  })
}
# Logging only. A replica writes to /aws/lambda/us-east-1.<function> in the region of the edge location that
# ran it, so there is no single log group to pre-create; CreateLogGroup stays in this policy for that reason.
resource "aws_iam_role_policy_attachment" "lambda_edge_logs" {
  role       = aws_iam_role.lambda_edge.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
data "archive_file" "function" {
  for_each    = var.functions
  type        = "zip"
  source_file = each.value.source_file
  output_path = "${path.module}/build/${each.key}.zip"
}
resource "aws_lambda_function" "function" {
  for_each         = var.functions
  function_name    = "${var.name_prefix}-${each.key}"
  description      = each.value.description
  runtime          = var.runtime
  handler          = "index.handler"
  role             = aws_iam_role.lambda_edge.arn
  filename         = data.archive_file.function[each.key].output_path
  source_code_hash = data.archive_file.function[each.key].output_base64sha256
  # Lambda@Edge limits for a viewer trigger: 5 seconds and 128 MB. A larger value is accepted here and then
  # rejected by CloudFront when the distribution associates the version.
  timeout     = 5
  memory_size = 128
  # A distribution associates a numbered version, never $LATEST. publish = true creates one on every code
  # change; qualified_arn is that version. It replaces the _monolithic template's AWS::Lambda::Version
  # resources, which the conversion could not carry over.
  publish = true
  timeouts {
    # A function CloudFront has replicated cannot be deleted until CloudFront removes the replicas, which it
    # does some time after the distribution stops referencing the version - often half an hour or more. The
    # provider retries "because it is a replicated function" for this long; the default 10 minutes is usually
    # not enough and the destroy fails with that message.
    delete = var.delete_timeout
  }
  depends_on = [aws_iam_role_policy_attachment.lambda_edge_logs]
}
