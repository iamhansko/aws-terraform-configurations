# The queue Karpenter watches for notices that a node is about to go away, and the four
# EventBridge rules that feed it.
#
# This is what turns a spot interruption from an abrupt loss into a drain: Karpenter polls the
# queue, and on a notice it cordons the node, evicts its pods and provisions a replacement
# before the two minutes are up. Without it the instance simply disappears and the pods are
# rescheduled after the node goes NotReady.
#
# Its own module rather than part of the karpenter module, because the queue and the rules are
# AWS resources with no Kubernetes side, and the controller module is handed the queue's name
# rather than creating it (rules.md B-6).
data "aws_caller_identity" "current" {}
resource "aws_sqs_queue" "karpenter_interruption_queue" {
  name                      = var.name
  message_retention_seconds = var.message_retention_seconds
  sqs_managed_sse_enabled   = var.sqs_managed_sse_enabled
}
resource "aws_sqs_queue_policy" "karpenter_interruption_queue" {
  # A single queue URL, not a JSON array of one.
  #
  # The _monolithic template had queue_url = jsonencode([aws_sqs_queue...id]) here, which is
  # the same list-to-scalar mistake rules.md A-3 describes for
  # aws_iam_instance_profile.role - CloudFormation's AWS::SQS::QueuePolicy takes a Queues
  # list, and the conversion carried the list across to an attribute that takes one string.
  # It passes terraform validate, because the attribute is a string either way, and fails at
  # apply with an SQS API error about a malformed queue URL. Worth noting that the audit
  # command in A-3 greps for "role = jsonencode([", so it does not catch this one.
  queue_url = aws_sqs_queue.karpenter_interruption_queue.id

  policy = jsonencode({
    # Version, which was missing - and its absence is what made this resource hang rather than
    # fail. SQS defaults an unversioned policy to the legacy 2008-10-17 and returns that, so the
    # provider's create waiter compared the document it sent against one carrying a Version it had
    # never set, never saw them as equal, and ran out its timeout:
    #
    #   Error: waiting for SQS Queue (...) attribute (Policy) create: timeout while waiting for
    #     state to become 'equal' (last state: 'notequal', timeout: 19m59s)
    #
    # The policy itself applied immediately and correctly; only the comparison failed. Confirmed by
    # reading the stored policy back with sqs get-queue-attributes, which showed the added Version.
    Version = "2012-10-17"
    Id      = "EC2InterruptionPolicy"
    Statement = [
      {
        Sid    = "AllowEventBridgeAndSQSToSendMessages"
        Effect = "Allow"
        Principal = {
          Service = ["events.amazonaws.com", "sqs.amazonaws.com"]
        }
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.karpenter_interruption_queue.arn
        Condition = {
          # Confused deputy protection, which the _monolithic template's policy omitted:
          # without it any account's EventBridge rule could write to this queue, and
          # Karpenter would act on notices about instances that are not ours.
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },
      {
        Sid      = "DenyHTTP"
        Effect   = "Deny"
        Action   = "sqs:*"
        Resource = aws_sqs_queue.karpenter_interruption_queue.arn
        Condition = {
          Bool = {
            # A string, not a JSON boolean. IAM condition values are strings, and SQS coerces a
            # bare false to "false" and returns it that way - a second difference between what the
            # provider sends and what it reads back, on top of the missing Version above.
            "aws:SecureTransport" = "false"
          }
        }
        Principal = "*"
      },
    ]
  })
}
locals {
  # Keys are literal strings, so every for_each below is known during plan even though the
  # queue ARN is not (rules.md B-8). One entry per rule keeps the four EventBridge rules and
  # their four targets as two resources rather than eight, where the _monolithic template
  # wrote each out separately (rules.md B-7).
  rules = merge(
    var.enable_scheduled_change_rule ? {
      scheduled_change = {
        description = "AWS Health scheduled changes - planned retirement or maintenance of an instance"
        pattern = merge(
          {
            source        = ["aws.health"]
            "detail-type" = ["AWS Health Event"]
          },
          # Narrows the match to EC2. See var.health_event_service_filter.
          length(var.health_event_service_filter) > 0 ? {
            detail = { service = var.health_event_service_filter }
          } : {},
        )
      }
    } : {},
    var.enable_spot_interruption_rule ? {
      spot_interruption = {
        description = "EC2 spot interruption warnings - two minutes of notice before the instance is reclaimed"
        pattern = {
          source        = ["aws.ec2"]
          "detail-type" = ["EC2 Spot Instance Interruption Warning"]
        }
      }
    } : {},
    var.enable_rebalance_rule ? {
      rebalance = {
        description = "EC2 rebalance recommendations - capacity at elevated risk, weaker than an interruption warning"
        pattern = {
          source        = ["aws.ec2"]
          "detail-type" = ["EC2 Instance Rebalance Recommendation"]
        }
      }
    } : {},
    var.enable_instance_state_change_rule ? {
      instance_state_change = {
        description = "EC2 instance state changes - the only signal for an instance that is stopped or terminated outright, with no interruption warning"
        pattern = {
          source        = ["aws.ec2"]
          "detail-type" = ["EC2 Instance State-change Notification"]
        }
      }
    } : {},
  )
}
resource "aws_cloudwatch_event_rule" "karpenter_interruption" {
  for_each = local.rules

  # Named rather than left to Terraform's generated terraform-<hash>, so the rules are
  # identifiable in the EventBridge console and two deployments in one account do not read as
  # eight anonymous rules.
  name          = "${var.name}-${replace(each.key, "_", "-")}"
  description   = each.value.description
  event_pattern = jsonencode(each.value.pattern)
}
resource "aws_cloudwatch_event_target" "karpenter_interruption" {
  for_each = aws_cloudwatch_event_rule.karpenter_interruption

  rule      = each.value.name
  arn       = aws_sqs_queue.karpenter_interruption_queue.arn
  target_id = "KarpenterInterruptionQueueTarget"

  # EventBridge can only deliver once the queue policy admits it, and referencing the queue's
  # ARN does not order this after the policy (rules.md D-1). Without the edge a notice
  # arriving in the window between the two is dropped, which is invisible - EventBridge counts
  # it as a failed invocation and nothing else reports it.
  depends_on = [aws_sqs_queue_policy.karpenter_interruption_queue]
}
