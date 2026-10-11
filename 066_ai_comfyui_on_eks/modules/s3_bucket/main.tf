# One private bucket. The blueprint's buckets came from CDK's s3.Bucket defaults - public access blocked,
# SSE-S3, ACLs disabled - so those are stated here explicitly rather than left to the account's defaults.
#
# What makes a bucket special (access logging into another bucket, the notification that drives the model
# sync Lambda, the log delivery policy) joins two resources that do not know about each other, so it is
# declared in the root rather than here (rules.md C-1).
resource "aws_s3_bucket" "bucket" {
  bucket        = var.bucket_name
  force_destroy = var.force_destroy
  tags          = merge(var.tags, { Name = var.bucket_name })
}
resource "aws_s3_bucket_public_access_block" "bucket" {
  bucket                  = aws_s3_bucket.bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
# BucketOwnerEnforced disables ACLs, which is what makes a bucket policy - not a log-delivery ACL - the way
# S3 server access logs are allowed in.
resource "aws_s3_bucket_ownership_controls" "bucket" {
  bucket = aws_s3_bucket.bucket.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}
resource "aws_s3_bucket_server_side_encryption_configuration" "bucket" {
  bucket = aws_s3_bucket.bucket.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
resource "aws_s3_bucket_lifecycle_configuration" "bucket" {
  count = var.expiration_days == null ? 0 : 1

  bucket = aws_s3_bucket.bucket.id
  rule {
    id     = "expire-after-${var.expiration_days}-days"
    status = "Enabled"
    filter {}
    expiration {
      days = var.expiration_days
    }
  }
}
