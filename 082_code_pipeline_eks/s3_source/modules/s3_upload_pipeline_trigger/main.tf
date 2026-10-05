# What starts the pipeline when a new archive is uploaded.
#
# CodePipeline's S3 source has two change detection methods: polling the object every minute, which is the
# default and which AWS recommends against, or an EventBridge rule. The source stage here sets
# PollForSourceChanges to false, so this rule is the only thing that starts a run - without it the pipeline
# exists, works when started by hand, and an upload changes nothing.
#
# The _monolithic template had a rule and left PollForSourceChanges unset, which defaults to true: it got
# both mechanisms at once, so an upload started a run through the rule and the pipeline also polled the
# bucket forever afterwards.
resource "aws_cloudwatch_event_rule" "object_created" {
  name        = "${var.name}-s3-upload"
  description = "Starts the ${var.pipeline_name} pipeline when ${var.object_key} is uploaded to ${var.bucket_name}"
  state       = var.enabled ? "ENABLED" : "DISABLED"
  event_pattern = jsonencode({
    source = ["aws.s3"]
    # The S3 event notification form. The original matched "AWS API Call via CloudTrail" and the
    # CopyObject/PutObject/CompleteMultipartUpload API names, which is the path that needs a trail - this one
    # needs only the bucket's EventBridge notification flag, and covers a multipart upload without naming
    # the three operations that can produce one.
    "detail-type" = ["Object Created"]
    detail = {
      bucket = { name = [var.bucket_name] }
      # Narrower than the pattern AWS's template shows, which matches any object in the bucket. The pipeline
      # reads one key, so an upload of anything else would start an execution that redeploys what is already
      # there.
      object = { key = [var.object_key] }
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
  rule      = aws_cloudwatch_event_rule.object_created.name
  target_id = var.pipeline_name
  arn       = var.pipeline_arn
  role_arn  = aws_iam_role.events.arn

  # role_arn is an ARN reference, which orders this after the role but not after its policy
  # (rules.md D-1). A rule that fires before the policy lands fails to start the pipeline, and that failure
  # appears only in the rule's FailedInvocations metric.
  depends_on = [aws_iam_role_policy.events]
}
