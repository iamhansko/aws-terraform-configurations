# What starts the pipeline when an image is pushed.
#
# CodePipeline's ECR source provider does not poll: something has to tell the pipeline a new image
# arrived, and that something is an EventBridge rule on the registry's push event. Without it the pipeline
# exists, its source stage works when run by hand, and a push changes nothing - which looks like a broken
# source stage rather than a missing rule.
resource "aws_cloudwatch_event_rule" "ecr_push" {
  name        = "${var.name}-ecr-push"
  description = "Starts the ${var.pipeline_name} pipeline when an image is pushed to ${var.repository_name}:${var.image_tag}"
  state       = var.enabled ? "ENABLED" : "DISABLED"

  event_pattern = jsonencode({
    source        = ["aws.ecr"]
    "detail-type" = ["ECR Image Action"]
    detail = {
      "action-type"     = ["PUSH"]
      "image-tag"       = [var.image_tag]
      "repository-name" = [var.repository_name]
      # Only successful pushes. Without this a failed upload also starts the pipeline, which then deploys
      # whatever image was there before.
      result = ["SUCCESS"]
    }
  })
}
resource "aws_iam_role" "events" {
  name_prefix = "${substr(var.name, 0, 24)}-evt-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}
resource "aws_iam_role_policy" "events" {
  name = "start-pipeline"
  role = aws_iam_role.events.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["codepipeline:StartPipelineExecution"]
      Resource = [var.pipeline_arn]
    }]
  })
}
resource "aws_cloudwatch_event_target" "pipeline" {
  rule      = aws_cloudwatch_event_rule.ecr_push.name
  target_id = var.pipeline_name
  arn       = var.pipeline_arn
  role_arn  = aws_iam_role.events.arn

  # role_arn is an ARN reference, which orders this after the role but not after its policy
  # (rules.md D-1). A rule that fires before the policy lands fails to start the pipeline and the failure
  # is only visible in the rule's FailedInvocations metric.
  depends_on = [aws_iam_role_policy.events]
}
