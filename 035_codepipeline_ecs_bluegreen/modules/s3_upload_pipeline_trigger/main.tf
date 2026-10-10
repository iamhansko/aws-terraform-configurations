# What starts the pipeline when a new archive is uploaded.
#
# A CodePipeline S3 source has two change detection methods: polling the object every minute, which is
# the default and which AWS recommends against, or an EventBridge rule. The source action here sets
# PollForSourceChanges to false, so this rule is the only thing that starts a run - without it the
# pipeline exists, works when started by hand, and an upload changes nothing.
#
# The pattern matches the CloudTrail form rather than the S3 notification form, which is what makes the
# trail part of the chain. Both halves are required and they fail differently: with no trail the rule
# is correct and silent, and with no rule the trail records the write and nothing acts on it.
resource "aws_cloudwatch_event_rule" "object_created" {
  name           = var.name
  description    = var.description
  event_bus_name = var.event_bus_name
  state          = var.enabled ? "ENABLED" : "DISABLED"
  event_pattern = jsonencode({
    source = ["aws.s3"]
    # This detail-type is delivered only for API calls a trail is recording, and an object PUT is a
    # data event - so the trail's event selector has to name this object at the object level. A trail
    # with management events only produces nothing here.
    "detail-type" = ["AWS API Call via CloudTrail"]
    detail = {
      eventSource = ["s3.amazonaws.com"]
      # Three operations, as the _monolithic template had them, and all three are needed: a small
      # upload is a PutObject, one large enough for the CLI to split is a CompleteMultipartUpload, and
      # a copy within S3 is a CopyObject. Naming only PutObject is how a rule comes to work for a
      # person's test upload and not for a script's.
      eventName = var.event_names
      requestParameters = {
        # Narrower than matching the whole bucket, which is deliberate. The pipeline reads one key, so
        # an upload of anything else would start an execution that redeploys what is already there -
        # and this bucket's trail selector is scoped to the same single object for the same reason.
        bucketName = [var.bucket_name]
        key        = [var.object_key]
      }
    }
  })
}
resource "aws_iam_role" "event_rule_iam_role" {
  # A generated name, where the _monolithic template used "CloudWatchEventRuleRole-${local.stack_suffix}".
  name_prefix = var.role_name_prefix
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = ["events.amazonaws.com"]
      }
      Action = ["sts:AssumeRole"]
    }]
  })
}
# One action on one resource, which is what the _monolithic template had and is the right shape - this
# is the one role in the project that needed no narrowing (rules.md A-5).
resource "aws_iam_role_policy" "event_rule_iam_role" {
  name = "start-pipeline"
  role = aws_iam_role.event_rule_iam_role.name
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
  rule           = aws_cloudwatch_event_rule.object_created.name
  event_bus_name = var.event_bus_name
  target_id      = var.target_id
  # The pipeline's real ARN, where the _monolithic template assembled one from a literal pipeline name.
  # Both produce the same string; this one also creates the dependency edge, so the target cannot be
  # created before the pipeline it points at.
  arn      = var.pipeline_arn
  role_arn = aws_iam_role.event_rule_iam_role.arn

  # role_arn references the role but not the policy on it, and the _monolithic template had no edge
  # here at all. A rule that fires before the policy lands fails to start the pipeline, and that
  # failure appears nowhere except the rule's FailedInvocations metric - the pipeline just looks as
  # though nothing was uploaded (rules.md D-1).
  depends_on = [aws_iam_role_policy.event_rule_iam_role]
}
