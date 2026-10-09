# The AWS Config plumbing: a delivery bucket, the role Config assumes, the recorder, the delivery
# channel, and the call that starts recording.
#
# These five belong in one module because the order they are created in is the whole difficulty, and
# that order is circular on its face:
#
#   PutDeliveryChannel fails with NoAvailableConfigurationRecorderException if no recorder exists.
#   StartConfigurationRecorder fails if no delivery channel exists.
#
# It resolves because creating a recorder and starting one are two different API calls, so the real
# chain is linear: bucket -> bucket policy -> recorder (created, stopped) -> delivery channel ->
# recorder started. Terraform models the last step as its own resource, which is what makes the chain
# expressible at all.
#
# The _monolithic template had three of these five. There was no bucket policy and no start, and both
# gaps are described on the resources below.
resource "aws_s3_bucket" "config_bucket" {
  bucket_prefix = var.bucket_name_prefix
  force_destroy = var.bucket_force_destroy
}
# Not in the _monolithic template, which declared a bare bucket.
#
# Safe to turn all four on here, unlike the website bucket in 097: the only principal this bucket's
# policy names is the config.amazonaws.com service, and a service principal is not a public grant, so
# block_public_policy does not reject the policy below. A Config delivery bucket holds a full
# inventory of the account's resource configurations, which is the last thing that should be world
# readable by accident.
resource "aws_s3_bucket_public_access_block" "config_bucket" {
  bucket                  = aws_s3_bucket.config_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
# Also not in the original. SSE-S3 rather than SSE-KMS deliberately: a KMS key would need its own key
# policy entry for config.amazonaws.com and an extra kms:GenerateDataKey grant on the role below, and
# getting either wrong fails delivery silently - objects simply stop appearing in the bucket.
resource "aws_s3_bucket_server_side_encryption_configuration" "config_bucket" {
  bucket = aws_s3_bucket.config_bucket.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
# This policy is missing from the _monolithic template, and its absence is not cosmetic: it makes that
# template fail at apply.
#
# PutDeliveryChannel reads the target bucket's policy and rejects the call if it does not already
# permit the service to write, with InsufficientDeliveryPolicyException ("Insufficient delivery policy
# to s3 bucket: <name>, unable to write to bucket"). The console adds this policy for you, which is
# why a template converted from a console-built stack can be missing it. So the original would have
# created the bucket, the roles, the Lambda and the recorder, then stopped on the delivery channel.
#
# The three statements are AWS's documented set and all three are needed: Config checks the bucket's
# ACL and its existence before it writes anything, so granting only PutObject fails the same check.
# The SourceAccount conditions are AWS's recommended confused-deputy guard - without them the policy
# lets Config write here on behalf of any account that names this bucket.
resource "aws_s3_bucket_policy" "config_bucket" {
  bucket = aws_s3_bucket.config_bucket.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AWSConfigBucketPermissionsCheck"
        Effect    = "Allow"
        Principal = { Service = "config.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.config_bucket.arn
        Condition = {
          StringEquals = { "AWS:SourceAccount" = var.account_id }
        }
      },
      {
        Sid       = "AWSConfigBucketExistenceCheck"
        Effect    = "Allow"
        Principal = { Service = "config.amazonaws.com" }
        Action    = "s3:ListBucket"
        Resource  = aws_s3_bucket.config_bucket.arn
        Condition = {
          StringEquals = { "AWS:SourceAccount" = var.account_id }
        }
      },
      {
        Sid       = "AWSConfigBucketDelivery"
        Effect    = "Allow"
        Principal = { Service = "config.amazonaws.com" }
        Action    = "s3:PutObject"
        # Config writes under AWSLogs/<account>/Config/, so the grant stops there rather than
        # covering the whole bucket.
        Resource = "${aws_s3_bucket.config_bucket.arn}/AWSLogs/${var.account_id}/Config/*"
        Condition = {
          StringEquals = {
            # Config sends this canned ACL on every object. Requiring it keeps an object that would
            # not be fully owned by this account out of the bucket - and it is also the one canned
            # ACL S3 still accepts on a bucket where object ownership is enforced, which is the
            # default for buckets created now.
            "s3:x-amz-acl"      = "bucket-owner-full-control"
            "AWS:SourceAccount" = var.account_id
          }
        }
      },
    ]
  })
}
# The role Config assumes to describe resources and to write to the bucket.
#
# The SourceAccount condition is not in the original trust policy. It restricts the service principal
# to assuming this role on behalf of this account only, which is AWS's documented form for a Config
# role; the demo is single-account, so it costs nothing here and removes a cross-account path.
resource "aws_iam_role" "config_service_role" {
  name_prefix = var.role_name_prefix
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "config.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = { "AWS:SourceAccount" = var.account_id }
      }
    }]
  })
}
# The _monolithic template attached AdministratorAccess to this role. It is narrowed to AWS_ConfigRole
# here, and that is a change to what the original did rather than a faithful conversion, so it is
# recorded at the point of change as well as in the caller's variable (rules.md A-5).
#
# The judgement is the straightforward half of A-5: this is a service role whose entire job is
# Describe and List, AWS publishes a policy for exactly that job, and the original was not hiding a
# narrower policy in a bootstrap script - it really did attach Administrator. Nothing about the demo
# depends on Config being able to do more than read.
resource "aws_iam_role_policy_attachment" "config_service_role" {
  for_each   = toset(var.role_policy_arns)
  role       = aws_iam_role.config_service_role.name
  policy_arn = each.value
}
# The half of the narrowing that is easy to get wrong.
#
# AWS_ConfigRole grants no write access to any bucket, so swapping AdministratorAccess for it and
# stopping there produces a recorder that starts, records, and then fails every delivery. That failure
# is quiet: the recorder stays ACTIVE and describe-configuration-recorder-status reports a
# lastStatus of FAILURE with a message naming the bucket, which nothing surfaces unless it is looked
# at. Hence the explicit grant, scoped to this bucket and this account's prefix.
#
# PutObjectAcl is here because the delivery sends the bucket-owner-full-control canned ACL that the
# bucket policy above requires.
resource "aws_iam_role_policy" "config_service_role_delivery" {
  name = "config-delivery-to-${aws_s3_bucket.config_bucket.id}"
  role = aws_iam_role.config_service_role.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:PutObjectAcl"]
        Resource = "${aws_s3_bucket.config_bucket.arn}/AWSLogs/${var.account_id}/*"
        Condition = {
          StringLike = { "s3:x-amz-acl" = "bucket-owner-full-control" }
        }
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetBucketAcl", "s3:ListBucket"]
        Resource = aws_s3_bucket.config_bucket.arn
      },
    ]
  })
}
# The recorder. Created, not started - see aws_config_configuration_recorder_status below.
#
# The recording group is the _monolithic template's: record everything except the four IAM types the
# caller passes in. all_supported and include_global_resource_types have to be false and
# resource_types has to be empty when the strategy is EXCLUSION_BY_RESOURCE_TYPES; the provider
# rejects any other combination, which is why those three lines look redundant next to the strategy.
resource "aws_config_configuration_recorder" "config_recorder" {
  name     = var.recorder_name
  role_arn = aws_iam_role.config_service_role.arn
  recording_group {
    all_supported                 = false
    include_global_resource_types = false
    resource_types                = []
    exclusion_by_resource_types {
      resource_types = var.excluded_resource_types
    }
    recording_strategy {
      use_only = "EXCLUSION_BY_RESOURCE_TYPES"
    }
  }
  recording_mode {
    recording_frequency = var.recording_frequency
  }

  # role_arn orders this after the role but after neither the managed policy attachment nor the
  # delivery policy - nothing in this resource refers to them. Both have to be in place first:
  # PutConfigurationRecorder validates that the role can be assumed, and a recorder created with a
  # bare role records nothing until the policies land, with no error to say so (rules.md D-1).
  depends_on = [
    aws_iam_role_policy_attachment.config_service_role,
    aws_iam_role_policy.config_service_role_delivery,
  ]
}
resource "aws_config_delivery_channel" "delivery_channel" {
  name           = var.delivery_channel_name
  s3_bucket_name = aws_s3_bucket.config_bucket.id
  # The _monolithic template carried this as a ConfigSnapshotDeliveryProperties block that cfn2tf
  # could not map and left behind as a TODO comment, so the converted template delivered no periodic
  # snapshots at all. aws_config_delivery_channel does have the field.
  snapshot_delivery_properties {
    delivery_frequency = var.snapshot_delivery_frequency
  }

  # Two edges that no attribute reference creates, and both are hard failures rather than races:
  # PutDeliveryChannel rejects the call with NoAvailableConfigurationRecorderException when no
  # recorder exists, and with InsufficientDeliveryPolicyException when the bucket policy does not yet
  # permit the service to write. s3_bucket_name references the bucket, which orders this after the
  # bucket itself and after nothing else (rules.md D-1).
  depends_on = [
    aws_config_configuration_recorder.config_recorder,
    aws_s3_bucket_policy.config_bucket,
  ]
}
# Starting the recorder, which the _monolithic template did not do and did not need to.
#
# CloudFormation's AWS::Config::ConfigurationRecorder starts the recorder as soon as a delivery
# channel is available. Terraform's aws_config_configuration_recorder is only the
# PutConfigurationRecorder call, which leaves the recorder stopped. So the conversion dropped the
# start without dropping a line of configuration, and the result is the most confusing possible
# outcome for this project: apply succeeds, every resource exists, the rule is listed in the console,
# and it evaluates nothing forever because a stopped recorder produces no configuration items for a
# change-triggered rule to react to. Restoring it is restoring the original's behaviour rather than
# adding to it.
#
# The depends_on is the second half of the apparent cycle at the top of this file:
# StartConfigurationRecorder requires a delivery channel, and nothing in this resource refers to one
# (rules.md D-1). On destroy the same edge runs backwards and stops the recorder before the channel is
# deleted, which is required - DeleteDeliveryChannel fails while the recorder is running.
resource "aws_config_configuration_recorder_status" "config_recorder" {
  name       = aws_config_configuration_recorder.config_recorder.name
  is_enabled = var.recorder_enabled

  depends_on = [aws_config_delivery_channel.delivery_channel]
}
