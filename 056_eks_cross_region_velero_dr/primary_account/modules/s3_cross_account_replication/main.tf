# S3 replication from this account's backup bucket to a bucket in another account, and the role S3
# assumes to do it.
#
# This is the source half of a coupling that spans two accounts and therefore two state files. The
# destination bucket and its policy are in the other account's root, and nothing here can reference
# them - so every value that crosses the boundary crosses as a literal string (rules.md I-1/I-2).
#
# The circularity that forces that, spelled out because it decides the whole shape of this module:
#
#   this side  needs the destination bucket's name, to point the replication rule at it
#   that side  needs this role's ARN, to write a bucket policy admitting it
#
# Neither can be applied first if each waits for the other's output. The way out is that both sides
# agree on names beforehand - this module is handed a destination bucket name, and it is handed the
# role name it should create rather than generating one, so the other account can name that role
# without asking. That agreement is why role_name is required here while every other role in this
# project uses name_prefix (rules.md I-2).
resource "aws_iam_role" "s3_replication" {
  # A fixed name, deliberately. The destination account's bucket policy names this role as a literal
  # principal ARN, so a generated name would leave that policy pointing at a role that does not
  # exist - and replication would then fail silently, since a denied replication is reported only in
  # the object's replication status.
  name = var.role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "s3.amazonaws.com"
      }
      Action = "sts:AssumeRole"
      Condition = {
        # Confused deputy protection, which the _monolithic template's trust policy omitted. Without
        # it S3 in any account could assume this role; with it, only replication started by this
        # account's buckets can.
        StringEquals = {
          "aws:SourceAccount" = var.source_account_id
        }
      }
    }]
  })
}
resource "aws_iam_role_policy" "s3_replication" {
  name = "replication"
  role = aws_iam_role.s3_replication.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Reads on the source bucket. Scoped to it, where the _monolithic template granted all ten of
        # these actions on "*" - which is read access to every object version in every bucket in the
        # account, assumable by S3.
        Sid    = "ReadSourceBucket"
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetReplicationConfiguration",
        ]
        Resource = var.source_bucket_arn
      },
      {
        Sid    = "ReadSourceObjects"
        Effect = "Allow"
        Action = [
          "s3:GetObjectVersionForReplication",
          "s3:GetObjectVersionAcl",
          "s3:GetObjectVersionTagging",
          "s3:GetObjectRetention",
          "s3:GetObjectLegalHold",
        ]
        Resource = "${var.source_bucket_arn}/*"
      },
      {
        # Writes on the destination bucket, which is in another account. The ARN is assembled from a
        # name rather than referenced, because that bucket is in a different state file - and it is
        # only half of what is needed: the destination's own bucket policy has to admit this role as
        # well, since cross-account access needs a grant on both sides (rules.md I-2).
        Sid    = "WriteDestinationObjects"
        Effect = "Allow"
        Action = [
          "s3:ReplicateObject",
          "s3:ReplicateDelete",
          "s3:ReplicateTags",
          "s3:ObjectOwnerOverrideToBucketOwner",
        ]
        Resource = "arn:aws:s3:::${var.destination_bucket_name}/*"
      },
    ]
  })
}
resource "aws_s3_bucket_replication_configuration" "s3_replication" {
  bucket = var.source_bucket_name
  role   = aws_iam_role.s3_replication.arn

  rule {
    id       = var.rule_id
    status   = "Enabled"
    priority = var.priority

    # An empty prefix filter, as the _monolithic template had it: every object is replicated. A prefix
    # of "backups/" would cover Velero's backup objects and miss the metadata it writes alongside
    # them, which is the kind of narrowing that produces a destination bucket a restore cannot read.
    filter {
      prefix = var.prefix
    }

    # Required whenever a filter is present, and the _monolithic template left it out - which the API
    # accepts, defaulting to Disabled. The effect is subtle and bad for a backup bucket: a backup
    # deleted on the source stays on the destination forever, so the destination accumulates backups
    # Velero has already expired and its lifecycle rules never see them.
    delete_marker_replication {
      status = var.delete_marker_replication_status
    }

    # The source bucket uses SSE-S3 (AES256), which S3 replication copies without any
    # source_selection_criteria. Emitting sse_kms_encrypted_objects even with status = "Disabled"
    # makes PutBucketReplication require a ReplicaKmsKeyID; that block belongs only to replication
    # of SSE-KMS objects.

    destination {
      bucket = "arn:aws:s3:::${var.destination_bucket_name}"
      # The destination is in another account, so this has to be stated. Without it S3 rejects the
      # configuration - it will not replicate across an account boundary without being told which
      # account it is crossing into.
      account = var.destination_account_id

      # The replica is owned by the destination account rather than by this one. Without this the
      # objects arrive owned by the source account, sitting in someone else's bucket, and the
      # destination cluster's Velero cannot read them - it has no permission on objects its own
      # account does not own. The _monolithic template granted the role
      # s3:ObjectOwnerOverrideToBucketOwner and then never asked for the override, so its replicas
      # were unreadable on the receiving side.
      access_control_translation {
        owner = "Destination"
      }

      dynamic "metrics" {
        for_each = var.replication_time_minutes == null ? [] : [1]

        content {
          status = "Enabled"
          event_threshold {
            minutes = var.replication_time_minutes
          }
        }
      }

      # Replication Time Control: S3 commits to replicating 99.99% of objects within this window and
      # emits metrics and events when it does not. It costs extra per gigabyte, which is worth
      # knowing before leaving it on - the _monolithic template had it on at 15 minutes without
      # saying so.
      dynamic "replication_time" {
        for_each = var.replication_time_minutes == null ? [] : [1]

        content {
          status = "Enabled"
          time {
            minutes = var.replication_time_minutes
          }
        }
      }
    }
  }

  # The policy has to be attached before S3 validates the configuration, and referencing only the
  # role's ARN does not order this after its policy (rules.md D-1). S3 checks the role can read the
  # source bucket when the configuration is created, so without this the create fails with a message
  # about the role rather than about the policy.
  depends_on = [aws_iam_role_policy.s3_replication]

  lifecycle {
    precondition {
      condition     = var.destination_account_id != var.source_account_id
      error_message = "destination_account_id must differ from source_account_id. Replicating a bucket into another bucket in the same account works, but it is not what this project is for - and the destination's bucket policy naming a role in its own account is a sign the two roots were applied with the same credentials (rules.md I-2)."
    }
  }
}
