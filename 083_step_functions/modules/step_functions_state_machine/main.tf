data "aws_region" "current" {}
data "aws_caller_identity" "current" {}
locals {
  # The definition as a typed HCL object rather than the heredoc JSON string with interpolations the
  # _monolithic template used. The reason is the same one that applies to Kubernetes manifests: a string is
  # not checked by anything until the service reads it, so a missing comma or a mistyped state name is an
  # apply-time failure - and interpolating an ARN into JSON by hand is where quoting goes wrong
  # (rules.md E-3 makes the same argument for manifests).
  definition = {
    Comment = var.comment
    StartAt = "ValidateData"
    States = {
      ValidateData = {
        Type     = "Task"
        Resource = var.validate_function_arn
        Next     = "IsValid"
      }
      IsValid = {
        Type = "Choice"
        Choices = [{
          # The field the validate function sets. The function returns isValid at the top level, so this is
          # $.isValid - a path that does not exist makes the Choice fall through to Default, which looks
          # exactly like a validation failure.
          Variable      = "$.isValid"
          BooleanEquals = true
          Next          = "ProcessData"
        }]
        Default = "NotifyFailed"
      }
      ProcessData = {
        Type     = "Task"
        Resource = var.process_function_arn
        Next     = "NotifySucceeded"
      }
      NotifySucceeded = {
        Type     = "Task"
        Resource = "arn:aws:states:::sns:publish"
        Parameters = {
          TopicArn = var.notification_topic_arn
          Message  = "StepFunction Succeeded"
          Subject  = "SUCCEEDED"
        }
        End = true
      }
      NotifyFailed = {
        Type     = "Task"
        Resource = "arn:aws:states:::sns:publish"
        Parameters = {
          TopicArn = var.notification_topic_arn
          Message  = "StepFunction Failed"
          Subject  = "FAILED"
        }
        End = true
      }
    }
  }
}
# Declared rather than left to Step Functions, for the same reason as a Lambda log group: retention, and a
# destroy that removes the logs. The name has to start with /aws/vendedlogs/ for Step Functions to accept it.
resource "aws_cloudwatch_log_group" "state_machine" {
  count             = var.log_level == "OFF" ? 0 : 1
  name              = "/aws/vendedlogs/states/${var.name}"
  retention_in_days = var.log_retention_days
}
resource "aws_iam_role" "state_machine" {
  name_prefix = "${substr(var.name, 0, 32)}-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "states.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = {
        # Scoped to this account and this state machine, which is the documented guard against a confused
        # deputy: without it any Step Functions state machine anywhere could assume this role.
        StringEquals = {
          "aws:SourceAccount" = data.aws_caller_identity.current.account_id
        }
        ArnLike = {
          "aws:SourceArn" = "arn:aws:states:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:stateMachine:${var.name}"
        }
      }
    }]
  })
}
# Scoped where the _monolithic template used "*" for everything, and with the managed AWSLambdaRole policy it
# also attached dropped - that policy grants lambda:InvokeFunction on every function in the account, which
# made the inline statement below meaningless (rules.md A-5).
resource "aws_iam_role_policy" "state_machine" {
  name = "state-machine"
  role = aws_iam_role.state_machine.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          Effect = "Allow"
          Action = "lambda:InvokeFunction"
          # The two functions this definition names, and nothing else.
          Resource = [var.validate_function_arn, var.process_function_arn]
        },
        {
          Effect   = "Allow"
          Action   = "sns:Publish"
          Resource = var.notification_topic_arn
        },
      ],
      # These have to be on "*", and it is not laziness: CloudWatch Logs' delivery APIs take no resource, so
      # AWS's own documented policy for Step Functions logging grants them account-wide. The log writes
      # underneath them are still confined to the group named in the logging configuration.
      var.log_level == "OFF" ? [] : [{
        Effect = "Allow"
        Action = [
          "logs:CreateLogDelivery",
          "logs:GetLogDelivery",
          "logs:UpdateLogDelivery",
          "logs:DeleteLogDelivery",
          "logs:ListLogDeliveries",
          "logs:PutResourcePolicy",
          "logs:DescribeResourcePolicies",
          "logs:DescribeLogGroups",
        ]
        Resource = "*"
      }],
      var.tracing_enabled ? [{
        Effect   = "Allow"
        Action   = ["xray:PutTraceSegments", "xray:PutTelemetryRecords", "xray:GetSamplingRules", "xray:GetSamplingTargets"]
        Resource = "*"
      }] : [],
    )
  })
}
resource "aws_sfn_state_machine" "state_machine" {
  name     = var.name
  role_arn = aws_iam_role.state_machine.arn
  # STANDARD, which is the default stated explicitly. EXPRESS would be cheaper for a run this short but has
  # no execution history to read afterwards, and the history is what this project is for.
  type       = "STANDARD"
  definition = jsonencode(local.definition)

  dynamic "logging_configuration" {
    for_each = var.log_level == "OFF" ? [] : [1]
    content {
      log_destination        = "${aws_cloudwatch_log_group.state_machine[0].arn}:*"
      include_execution_data = var.include_execution_data
      level                  = var.log_level
    }
  }

  tracing_configuration {
    enabled = var.tracing_enabled
  }

  # role_arn is an ARN reference, which orders this after the role but not after its policy (rules.md D-1).
  # A state machine created before the policy lands is accepted and its first execution fails on the first
  # task.
  depends_on = [aws_iam_role_policy.state_machine]
}
