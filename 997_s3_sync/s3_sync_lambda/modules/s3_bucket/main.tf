resource "aws_s3_bucket" "s3_bucket" {
  bucket        = var.bucket_name
  bucket_prefix = var.bucket_name == null ? var.bucket_name_prefix : null
  # This is the native replacement for the empty_s3_bucket custom resource in the
  # sibling variant: CloudFormation refuses to delete a non-empty bucket and
  # needs a Lambda to empty it first, whereas the S3 provider empties it as part
  # of the delete.
  force_destroy = var.force_destroy
}
resource "aws_s3_bucket_public_access_block" "s3_bucket" {
  bucket                  = aws_s3_bucket.s3_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
resource "aws_s3_bucket_ownership_controls" "s3_bucket" {
  bucket = aws_s3_bucket.s3_bucket.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}
resource "aws_s3_bucket_server_side_encryption_configuration" "s3_bucket" {
  bucket = aws_s3_bucket.s3_bucket.id
  rule {
    apply_server_side_encryption_by_default {
      # AES256 rather than aws:kms on purpose: with SSE-KMS an object's ETag is
      # no longer the MD5 of its contents, so the sync function's
      # ETag-vs-hash comparison would never match and every invocation would
      # re-upload every file.
      sse_algorithm = var.sse_algorithm
    }
    bucket_key_enabled = var.sse_algorithm == "aws:kms"
  }
}
resource "aws_s3_bucket_versioning" "s3_bucket" {
  count  = var.versioning_enabled ? 1 : 0
  bucket = aws_s3_bucket.s3_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}
