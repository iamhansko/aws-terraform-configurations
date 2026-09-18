data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

# The destination bucket, the delivery stream and the role the stream assumes are
# one module rather than three: a delivery stream cannot exist without a role that
# can already write to its destination, and neither the role nor the bucket has a
# use outside this pipeline. This is the same reasoning that keeps an IRSA role and
# its Helm release together (rules.md C-2) - what is strongly coupled stays in one
# module, and only genuinely separate concerns get joined at the root.
resource "aws_s3_bucket" "destination" {
  # CloudFormation generated the bucket name. Terraform needs one, and a prefix
  # rather than a fixed name keeps the project deployable twice in an account -
  # bucket names are globally unique, so a literal name is a collision waiting to
  # happen.
  bucket_prefix = var.bucket_prefix
  # A demo bucket that terraform destroy should actually be able to remove. Without
  # this the destroy fails on a bucket Firehose has written objects into, and the
  # only way out is emptying it by hand.
  force_destroy = var.force_destroy

  tags = {
    Name = var.bucket_prefix
  }
}
resource "aws_iam_role" "firehose_iam_role" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = ["firehose.amazonaws.com"]
      }
      Action = ["sts:AssumeRole"]
    }]
  })
}
resource "aws_iam_role_policy" "firehose_iam_role" {
  name = var.policy_name
  role = aws_iam_role.firehose_iam_role.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          Sid    = "S3Access"
          Effect = "Allow"
          Action = [
            "s3:AbortMultipartUpload",
            "s3:GetBucketLocation",
            "s3:GetObject",
            "s3:ListBucket",
            "s3:ListBucketMultipartUploads",
            "s3:PutObject",
          ]
          # Scoped to this bucket, from the resource's own ARN rather than a string
          # built out of the bucket name (rules.md B-5).
          Resource = [aws_s3_bucket.destination.arn, "${aws_s3_bucket.destination.arn}/*"]
        },
        {
          Sid    = "CloudWatchAccess"
          Effect = "Allow"
          Action = ["logs:PutLogEvents"]
          # Firehose writes its own delivery errors here. Without it a failing
          # delivery is invisible: records disappear and nothing says why.
          # Scoped to the group this module creates rather than the _monolithic
          # template's log-group:*, since this role has exactly one place to write.
          Resource = ["${aws_cloudwatch_log_group.delivery.arn}:log-stream:*"]
        },
      ],
      # The three statements below were unconditional in the _monolithic template
      # and are off by default here. This delivery stream's source is direct PUT
      # from Fluent Bit, its destination is unencrypted S3, and it has no
      # transform, so none of the three grants anything the pipeline uses - and
      # each is wide: kinesis on stream/*, kms on key/*, lambda on function:*:*.
      var.enable_kinesis_source_access ? [{
        Sid      = "KinesisAccess"
        Effect   = "Allow"
        Action   = ["kinesis:DescribeStream", "kinesis:GetShardIterator", "kinesis:GetRecords", "kinesis:ListShards"]
        Resource = ["arn:aws:kinesis:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:stream/*"]
      }] : [],
      var.enable_s3_kms_access ? [{
        Sid      = "KmsAccess"
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:GenerateDataKey"]
        Resource = ["arn:aws:kms:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:key/*"]
        Condition = {
          StringEquals = {
            "kms:ViaService" = "s3.${data.aws_region.current.region}.amazonaws.com"
          }
          StringLike = {
            "kms:EncryptionContext:aws:s3:arn" = "${aws_s3_bucket.destination.arn}/*"
          }
        }
      }] : [],
      var.enable_lambda_transform_access ? [{
        Sid      = "LambdaAccess"
        Effect   = "Allow"
        Action   = ["lambda:InvokeFunction", "lambda:GetFunctionConfiguration"]
        Resource = ["arn:aws:lambda:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:function:*:*"]
      }] : [],
    )
  })
}
# Firehose does not create this group itself - only the console does, as a side
# effect of ticking the error-logging box. Pointed at a group that does not exist,
# the stream drops its own error records too, which is the worst possible failure
# mode for a diagnostic channel. The names match what the service defaults to so
# the group is where anyone looking for it would look.
resource "aws_cloudwatch_log_group" "delivery" {
  name              = "/aws/kinesisfirehose/${var.name}"
  retention_in_days = var.log_retention_days
}
resource "aws_cloudwatch_log_stream" "delivery" {
  name           = "DestinationDelivery"
  log_group_name = aws_cloudwatch_log_group.delivery.name
}
resource "aws_kinesis_firehose_delivery_stream" "firehose" {
  name        = var.name
  destination = "extended_s3"

  extended_s3_configuration {
    bucket_arn         = aws_s3_bucket.destination.arn
    role_arn           = aws_iam_role.firehose_iam_role.arn
    buffering_size     = var.buffering_size_mb
    buffering_interval = var.buffering_interval_seconds
    compression_format = var.compression_format
    # Records Firehose accepted but could not deliver land here instead of being
    # dropped. Declared rather than omitted because the service supplies "error"
    # for an omitted value, so leaving it out produces a permanent plan diff.
    error_output_prefix = var.error_output_prefix

    cloudwatch_logging_options {
      enabled         = var.enable_cloudwatch_logging
      log_group_name  = aws_cloudwatch_log_group.delivery.name
      log_stream_name = aws_cloudwatch_log_stream.delivery.name
    }
  }

  # Firehose validates the role's S3 permissions when the stream is created, and
  # referencing the role's ARN alone does not order this after the inline policy
  # (rules.md D-1).
  depends_on = [aws_iam_role_policy.firehose_iam_role]
}
