# An AWS Backup vault for EKS cluster backups, the IAM role AWS Backup assumes, and the notification
# path that reports what a restore skipped.
#
# All in one module because none of it works alone: a vault with no role has nothing to run jobs as, a
# role with no vault has nowhere to put recovery points, and the notification topic exists only to
# carry this vault's events. Same reasoning that keeps a controller's IAM role beside its Helm release
# (rules.md C-2).
#
# An EKS backup produces a *composite* recovery point: one parent for the cluster's Kubernetes state
# and a child for each EBS volume, EFS file system and S3 bucket attached through a claim. That is why
# the role needs the S3 policies as well as the EKS ones - a cluster with a bucket-backed claim fails
# partway through the job otherwise, and the parent recovery point is reported COMPLETED with children
# missing.
resource "aws_backup_vault" "vault" {
  # Derived from the project rather than hardcoded. aws_backup_vault has no name_prefix argument, so
  # uniqueness has to come from the value the caller passes - and it matters, because the
  # _monolithic template named this vault "eks" outright and a vault cannot be renamed.
  name          = var.name
  force_destroy = var.force_destroy
  kms_key_arn   = var.kms_key_arn
  tags          = var.tags
}

resource "aws_iam_role" "backup" {
  name_prefix = "${var.name}-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "backup.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "backup" {
  for_each   = toset(var.iam_policy_arns)
  role       = aws_iam_role.backup.name
  policy_arn = each.value
}

# Where the vault's events go. The _monolithic template subscribed only
# EKS_RESTORE_OBJECT_FAILED and EKS_RESTORE_OBJECT_SKIPPED, which is the interesting pair: a restore
# that reports success can still have skipped objects, and the skip list is only on this topic.
resource "aws_sns_topic" "events" {
  name_prefix = "${var.name}-"
  tags        = var.tags
}

# AWS Backup publishes through the topic's resource policy rather than through an IAM role, so the
# topic has to allow backup.amazonaws.com explicitly. Without this the vault notification is created
# and no event is ever delivered - there is no error on either side.
resource "aws_sns_topic_policy" "events" {
  arn = aws_sns_topic.events.arn
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "backup.amazonaws.com" }
      Action    = "SNS:Publish"
      Resource  = aws_sns_topic.events.arn
    }]
  })
}

resource "aws_backup_vault_notifications" "vault" {
  backup_vault_name   = aws_backup_vault.vault.name
  sns_topic_arn       = aws_sns_topic.events.arn
  backup_vault_events = var.backup_vault_events

  # The topic policy has to admit AWS Backup before the vault is pointed at it, or the first event is
  # dropped silently. Referencing the topic ARN alone only orders this after the topic (rules.md D-1).
  depends_on = [aws_sns_topic_policy.events]
}

# A queue subscribed to the topic, so the events are still there to read when someone looks. The
# alternative - an email subscription - needs a confirmation click that no apply can perform.
resource "aws_sqs_queue" "events" {
  name_prefix                = "${var.name}-"
  message_retention_seconds  = var.message_retention_seconds
  visibility_timeout_seconds = var.visibility_timeout_seconds
  sqs_managed_sse_enabled    = true
  tags                       = var.tags
}

# The piece the _monolithic template left out. An SNS subscription does not grant SNS permission to
# write to the queue; the queue's own policy does. Without it the subscription is created and shows as
# Confirmed, and every message is rejected - so the queue stays empty and nothing reports why.
resource "aws_sqs_queue_policy" "events" {
  # A string, not a list. The _monolithic template wrote
  # queue_url = jsonencode([aws_sqs_queue.x.id]) for its Karpenter queue, which is the same
  # list-to-single-value mistake rules.md A-3 describes for instance profiles - a JSON array in a
  # field the API expects to be one URL.
  queue_url = aws_sqs_queue.events.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowSnsDelivery"
        Effect    = "Allow"
        Principal = { Service = "sns.amazonaws.com" }
        Action    = "sqs:SendMessage"
        Resource  = aws_sqs_queue.events.arn
        Condition = {
          # Scoped to this topic, so the queue does not accept messages from any other topic in the
          # account.
          ArnEquals = { "aws:SourceArn" = aws_sns_topic.events.arn }
        }
      },
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "sqs:*"
        Resource  = aws_sqs_queue.events.arn
        Condition = {
          Bool = { "aws:SecureTransport" = false }
        }
      },
    ]
  })
}

resource "aws_sns_topic_subscription" "events" {
  topic_arn = aws_sns_topic.events.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.events.arn
  # Raw message delivery off, so the SNS envelope with the event type is preserved - which is the part
  # worth reading for a skipped-object notification.
  raw_message_delivery = false

  depends_on = [aws_sqs_queue_policy.events]
}

# A plan, so backups keep happening rather than existing only as a command somebody ran once. The
# _monolithic template started one job from a shell in an SSM Association and left it there: the
# cluster had exactly one recovery point, taken before any of the workloads existed.
#
# Optional, because a schedule is not always wanted for a demo - but on by default, since a backup
# demo with no backup schedule is a vault (rules.md B-4).
resource "aws_backup_plan" "plan" {
  count = var.create_backup_plan ? 1 : 0

  name = "${var.name}-plan"

  rule {
    rule_name         = "cluster"
    target_vault_name = aws_backup_vault.vault.name
    schedule          = var.backup_schedule
    # How long AWS Backup waits for the job to start before giving up, and how long it lets it run.
    # An EKS backup walks every object in the cluster and every attached volume, so the default
    # completion window is worth raising rather than discovering it as an ABORTED job.
    start_window      = var.start_window_minutes
    completion_window = var.completion_window_minutes

    lifecycle {
      delete_after = var.delete_after_days
    }
  }

  tags = var.tags
}

resource "aws_backup_selection" "cluster" {
  count = var.create_backup_plan ? 1 : 0

  name         = "${var.name}-cluster"
  iam_role_arn = aws_iam_role.backup.arn
  plan_id      = aws_backup_plan.plan[0].id
  # The cluster ARN, handed in by the caller rather than discovered here. This module knows nothing
  # about the cluster beyond what to protect (rules.md B-6).
  resources = var.protected_resource_arns

  # The role must carry its policies before a job selects anything with it, and iam_role_arn alone only
  # orders this after the role (rules.md D-1).
  depends_on = [aws_iam_role_policy_attachment.backup]
}
