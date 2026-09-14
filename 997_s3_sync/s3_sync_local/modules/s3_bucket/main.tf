resource "aws_s3_bucket" "s3_bucket" {
  bucket        = var.bucket_name
  bucket_prefix = var.bucket_name == null ? var.bucket_name_prefix : null
  # force_destroy lets `terraform destroy` remove the bucket even if the
  # local-exec sync left objects in it (e.g. delete_on_destroy = false in
  # modules/s3_sync_local), without needing a custom-resource-style cleanup
  # step first.
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
