data "aws_caller_identity" "current" {}
# The key the delivery stream encrypts its buffer with.
#
# The _monolithic template created this key and its alias and then never used either: the stream's
# DeliveryStreamEncryptionConfigurationInput came through the CloudFormation conversion as a commented-out
# TODO, so the stream ran unencrypted beside a key that cost a dollar a month and protected nothing. The
# server_side_encryption block below is that property, restored.
resource "aws_kms_key" "delivery_stream" {
  description             = "Server-side encryption for the ${var.name} delivery stream"
  is_enabled              = true
  enable_key_rotation     = true
  rotation_period_in_days = var.kms_key_rotation_period_in_days
  deletion_window_in_days = var.kms_key_deletion_window_in_days
  # The account-root statement and nothing else, as the original had it. It delegates the key to IAM, which
  # is what lets Firehose create its grant with the credentials of whoever creates the stream - there is no
  # firehose.amazonaws.com statement to add.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "Default"
      Effect = "Allow"
      Principal = {
        AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
      }
      Action   = "kms:*"
      Resource = "*"
    }]
  })
}
# Named after the stream rather than after a slice of the uuid that stood in for AWS::StackId, so the alias
# says which stream it belongs to and two copies of the project differ by their stream name.
resource "aws_kms_alias" "delivery_stream" {
  name          = "alias/${var.name}"
  target_key_id = aws_kms_key.delivery_stream.key_id
}
# --- Destination -----------------------------------------------------------------------------------------
# bucket_prefix rather than a fixed name, which is what the uuid slice in the _monolithic template's
# "stream-destination-<suffix>" was approximating.
resource "aws_s3_bucket" "destination" {
  bucket_prefix = var.bucket_prefix
  # Firehose writes objects Terraform never created, so without this terraform destroy stops at
  # BucketNotEmpty. The cost is that the delivered logs go with it - see the variable.
  force_destroy = var.force_destroy
}
resource "aws_s3_bucket_public_access_block" "destination" {
  bucket                  = aws_s3_bucket.destination.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
resource "aws_s3_bucket_ownership_controls" "destination" {
  bucket = aws_s3_bucket.destination.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}
resource "aws_iam_role" "delivery_stream" {
  name_prefix = "${trimsuffix(substr(var.name, 0, 24), "-")}-"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "firehose.amazonaws.com" }
      Action    = "sts:AssumeRole"
      # Only this account's streams may assume it - the confused-deputy guard Firehose documents.
      Condition = {
        StringEquals = { "sts:ExternalId" = data.aws_caller_identity.current.account_id }
      }
    }]
  })
}
# The original's six S3 actions on this one bucket, unchanged - it was already scoped correctly.
resource "aws_iam_role_policy" "delivery_stream" {
  name = "S3Policy"
  role = aws_iam_role.delivery_stream.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:AbortMultipartUpload",
        "s3:GetBucketLocation",
        "s3:GetObject",
        "s3:ListBucket",
        "s3:ListBucketMultipartUploads",
        "s3:PutObject",
      ]
      Resource = [aws_s3_bucket.destination.arn, "${aws_s3_bucket.destination.arn}/*"]
    }]
  })
}
resource "aws_kinesis_firehose_delivery_stream" "delivery_stream" {
  # CloudFormation generated this name; Terraform requires one, so the caller derives it from the project
  # name as the _monolithic template did from the stack name.
  name        = var.name
  destination = "extended_s3"
  server_side_encryption {
    enabled  = true
    key_type = "CUSTOMER_MANAGED_CMK"
    key_arn  = aws_kms_key.delivery_stream.arn
  }
  extended_s3_configuration {
    bucket_arn          = aws_s3_bucket.destination.arn
    role_arn            = aws_iam_role.delivery_stream.arn
    prefix              = var.prefix
    error_output_prefix = var.error_output_prefix
    compression_format  = var.compression_format
    # How long a record can sit in the buffer before it reaches S3. This is the whole of the batch-versus-
    # stream contrast the project's README names: CloudWatch Logs hands each event over as it arrives, and
    # this is the only place it waits.
    buffering_interval = var.buffering_interval_seconds
    buffering_size     = var.buffering_size_mb
  }
  # The role has to be able to write to the bucket before the stream exists: Firehose validates the
  # destination on creation, and role_arn alone orders this after the role but not after its policy
  # (rules.md D-1).
  depends_on = [aws_iam_role_policy.delivery_stream]
}
