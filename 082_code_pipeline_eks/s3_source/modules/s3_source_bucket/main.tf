# The bucket the application archive is uploaded to, which in this variant is the pipeline's source.
#
# The _monolithic template declared "resource aws_s3_bucket ... {}" plus a versioning block, and versioning
# was the only thing it configured. Everything else below is an addition.
resource "aws_s3_bucket" "source" {
  bucket        = var.bucket_name
  bucket_prefix = var.bucket_name == null ? "${var.name}-source-" : null
  force_destroy = var.force_destroy
}
# Not optional, which is why the original had it. CodePipeline's S3 source reads a specific object version,
# and on a bucket without versioning the source stage fails.
resource "aws_s3_bucket_versioning" "source" {
  bucket = aws_s3_bucket.source.id
  versioning_configuration {
    status = "Enabled"
  }
}
resource "aws_s3_bucket_server_side_encryption_configuration" "source" {
  bucket = aws_s3_bucket.source.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
resource "aws_s3_bucket_public_access_block" "source" {
  bucket                  = aws_s3_bucket.source.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
# Versioning is mandatory here, so something has to remove the superseded archives or every upload is kept
# forever. The original turned versioning on and stopped there.
resource "aws_s3_bucket_lifecycle_configuration" "source" {
  count  = var.noncurrent_version_expiration_days == null ? 0 : 1
  bucket = aws_s3_bucket.source.id

  rule {
    id     = "expire-superseded-archives"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_expiration_days
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.source]
}
# What lets an EventBridge rule see an upload at all, and the reason this variant needs no CloudTrail.
#
# The _monolithic template took the older of the two documented paths: a trail with an S3 data event
# selector on this one key, a second bucket for the trail's own logs, and a bucket policy on that bucket -
# three resources feeding a rule that matched "AWS API Call via CloudTrail" and the
# CopyObject/PutObject/CompleteMultipartUpload API names. AWS documents the same pipeline built on S3 event
# notifications instead, matching detail-type "Object Created", and this flag is all of it.
#
# The trail's fixed name mattered on its own: "codepipeline-source-trail" is one per account, so two copies
# of that template could not coexist - the collision everything else here is named to avoid.
resource "aws_s3_bucket_notification" "eventbridge" {
  count       = var.enable_eventbridge_notifications ? 1 : 0
  bucket      = aws_s3_bucket.source.id
  eventbridge = true
}
