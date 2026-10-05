# What starts the pipeline when a commit lands on the branch.
#
# CodePipeline's CodeCommit source has two change detection methods: polling the repository, which is the
# default and which AWS recommends against, or an EventBridge rule. The source stage here sets
# PollForSourceChanges to false, so this rule is the only thing that starts a run - without it the pipeline
# exists, works when started by hand, and a push changes nothing.
#
# The trigger is a resource like any other here, which is the same reason the two sibling variants have a
# trigger module of their own.
resource "aws_cloudwatch_event_rule" "repository_state_change" {
  name        = "${var.name}-codecommit-push"
  description = "Starts the ${var.pipeline_name} pipeline when a commit lands on ${var.branch_name} in ${var.repository_name}"
  state       = var.enabled ? "ENABLED" : "DISABLED"
  event_pattern = jsonencode({
    source        = ["aws.codecommit"]
    "detail-type" = ["CodeCommit Repository State Change"]
    # Scoped to this repository. Without it the rule matches every CodeCommit repository in the account and
    # region, so a push to an unrelated one would start this pipeline.
    resources = [var.repository_arn]
    detail = {
      # referenceCreated as well as referenceUpdated, and that is not padding: the first push creates the
      # branch rather than updating it, so a rule matching only referenceUpdated would miss exactly the
      # push this project makes during its own apply - the one that produces the first deployment.
      event         = ["referenceCreated", "referenceUpdated"]
      referenceType = ["branch"]
      referenceName = [var.branch_name]
    }
  })
}
resource "aws_iam_role" "events" {
  name_prefix = "${substr(var.name, 0, 24)}-cc-evt-"
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
  rule      = aws_cloudwatch_event_rule.repository_state_change.name
  target_id = var.pipeline_name
  arn       = var.pipeline_arn
  role_arn  = aws_iam_role.events.arn

  # role_arn is an ARN reference, which orders this after the role but not after its policy
  # (rules.md D-1). A rule that fires before the policy lands fails to start the pipeline, and that failure
  # appears only in the rule's FailedInvocations metric - not in the pipeline, which simply never ran.
  depends_on = [aws_iam_role_policy.events]
}
