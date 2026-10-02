# The fault injection experiments, and the role FIS assumes to run them.
#
# A template is not an experiment: it describes one, and starting it is a separate API call
# that costs money and takes nodes away. So these are created and left unstarted, which is the
# right shape for infrastructure - the outputs carry the command to start one.
#
# Both templates find their targets by the Name tag Karpenter puts on the instances it
# provisions. That tag is the join between this module and the node pools, and it is the thing
# most likely to be silently wrong, which is why empty_target_resolution_mode stays at fail.
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
resource "aws_iam_role" "fis_iam_role" {
  name        = var.role_name
  name_prefix = var.role_name == null ? var.role_name_prefix : null

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = ["fis.amazonaws.com"]
      }
      Action = ["sts:AssumeRole"]
      Condition = {
        # Confused deputy protection, which the _monolithic template's trust policy omitted.
        # Without it the FIS service principal in any account could assume this role; with it,
        # only experiments in this account can.
        StringEquals = {
          "aws:SourceAccount" = data.aws_caller_identity.current.account_id
        }
        ArnLike = {
          "aws:SourceArn" = "arn:${data.aws_partition.current.partition}:fis:*:${data.aws_caller_identity.current.account_id}:experiment/*"
        }
      }
    }]
  })
}
resource "aws_iam_role_policy_attachment" "fis_iam_role" {
  for_each = toset(var.managed_policy_arns)

  role       = aws_iam_role.fis_iam_role.name
  policy_arn = each.value
}
locals {
  log_configuration_enabled = var.log_group_arn != null
}
# Experiment logging is a delivery FIS sets up on its own behalf, not a PutLogEvents call, so
# the permissions are the log-delivery ones rather than write access to the group. Without
# them the template is still created and the experiment still runs - it just produces no log,
# which is the quiet failure this policy exists to avoid.
#
# The four actions are account-level and reject a resource ARN, so they are scoped to "*";
# only the delivery target is narrowed, by there being exactly one log group to deliver to.
resource "aws_iam_role_policy" "fis_experiment_logging" {
  count = local.log_configuration_enabled ? 1 : 0

  name = "experiment-logging"
  role = aws_iam_role.fis_iam_role.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogDelivery",
        "logs:PutResourcePolicy",
        "logs:DescribeResourcePolicies",
        "logs:DescribeLogGroups",
      ]
      Resource = "*"
    }]
  })
}
# Stops an instance outright. No interruption warning is issued for this, so the only thing
# Karpenter can react to is the instance state change event.
resource "aws_fis_experiment_template" "stop_instance" {
  count = var.stop_instance_experiment == null ? 0 : 1

  description = var.stop_instance_experiment.description
  role_arn    = aws_iam_role.fis_iam_role.arn

  action {
    name      = "StopInstance"
    action_id = "aws:ec2:stop-instances"
    target {
      # The key is the action's own parameter name, fixed by the action; the value is the
      # target block's name below. Getting the key wrong is rejected at create time, which is
      # the one mistake here that does not wait until the experiment runs.
      key   = "Instances"
      value = "StopInstanceTarget"
    }
  }
  target {
    name           = "StopInstanceTarget"
    resource_type  = "aws:ec2:instance"
    selection_mode = var.stop_instance_experiment.selection_mode
    resource_tag {
      key = "Name"
      # The tag Karpenter writes onto the instances of one node pool. Injected rather than
      # restated, so the experiment cannot target a tag no pool applies (rules.md B-5).
      value = var.stop_instance_experiment.name_tag
    }
  }
  experiment_options {
    account_targeting = "single-account"
    # fail, not skip. See var.empty_target_resolution_mode.
    empty_target_resolution_mode = var.empty_target_resolution_mode
  }
  # No stop condition, as the _monolithic template had it. A stop condition is a CloudWatch
  # alarm that aborts the experiment, and there is no alarm here to point at - for anything
  # beyond a demo this is the guardrail to add.
  stop_condition {
    source = "none"
  }
  dynamic "log_configuration" {
    for_each = local.log_configuration_enabled ? [1] : []

    content {
      log_schema_version = 2
      cloudwatch_logs_configuration {
        log_group_arn = var.log_group_arn
      }
    }
  }

  # FIS checks at create time that the role it is handed can actually act, and referencing
  # the role's ARN says nothing about its policies being attached yet (rules.md D-1).
  depends_on = [
    aws_iam_role_policy_attachment.fis_iam_role,
    aws_iam_role_policy.fis_experiment_logging,
  ]
}
# Sends the real spot interruption warning, which is what exercises Karpenter's interruption
# queue rather than just its node health checks.
resource "aws_fis_experiment_template" "spot_interruption" {
  count = var.spot_interruption_experiment == null ? 0 : 1

  description = var.spot_interruption_experiment.description
  role_arn    = aws_iam_role.fis_iam_role.arn

  action {
    name      = "SpotInstanceInterruption"
    action_id = "aws:ec2:send-spot-instance-interruptions"
    parameter {
      # How long after the warning the instance is actually reclaimed, not how long until the
      # warning is sent - the warning is immediate. A long value leaves time to watch the
      # drain happen; the real AWS notice period is two minutes.
      key   = "durationBeforeInterruption"
      value = var.spot_interruption_experiment.duration_before_interruption
    }
    target {
      key   = "SpotInstances"
      value = "SpotInterruptionTarget"
    }
  }
  target {
    name = "SpotInterruptionTarget"
    # aws:ec2:spot-instance, not aws:ec2:instance. The action only accepts the spot resource
    # type, and a template built with the general one is rejected at create time.
    resource_type  = "aws:ec2:spot-instance"
    selection_mode = var.spot_interruption_experiment.selection_mode
    resource_tag {
      key   = "Name"
      value = var.spot_interruption_experiment.name_tag
    }
  }
  experiment_options {
    account_targeting            = "single-account"
    empty_target_resolution_mode = var.empty_target_resolution_mode
  }
  stop_condition {
    source = "none"
  }
  dynamic "log_configuration" {
    for_each = local.log_configuration_enabled ? [1] : []

    content {
      log_schema_version = 2
      cloudwatch_logs_configuration {
        log_group_arn = var.log_group_arn
      }
    }
  }

  # Same reasoning as the stop-instance template (rules.md D-1).
  depends_on = [
    aws_iam_role_policy_attachment.fis_iam_role,
    aws_iam_role_policy.fis_experiment_logging,
  ]
}
