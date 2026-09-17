resource "aws_s3_bucket" "s3_bucket" {
  bucket_prefix = var.bucket_prefix
  force_destroy = var.force_destroy
  tags = merge(var.tags, {
    Name = trimsuffix(var.bucket_prefix, "-")
  })
}
# Mountpoint writes through the S3 API like any other client, so the bucket only
# needs the defaults that keep it private. Declared explicitly rather than
# relying on account-level settings, which differ between accounts.
resource "aws_s3_bucket_public_access_block" "s3_bucket" {
  bucket                  = aws_s3_bucket.s3_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
resource "aws_s3_bucket_server_side_encryption_configuration" "s3_bucket" {
  bucket = aws_s3_bucket.s3_bucket.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
resource "aws_s3_bucket_versioning" "s3_bucket" {
  bucket = aws_s3_bucket.s3_bucket.id
  versioning_configuration {
    status = var.versioning_enabled ? "Enabled" : "Disabled"
  }
}
