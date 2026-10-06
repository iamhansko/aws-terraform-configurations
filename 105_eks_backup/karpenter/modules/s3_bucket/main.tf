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
# Lifecycle rules, when the caller has any. The whole resource is omitted otherwise rather than
# created with an empty rule set, which the API rejects (rules.md B-4).
#
# The _monolithic template declared one rule here, transitioning objects under a "glacier/" prefix to
# Glacier after 14 days and expiring them at a year. Kept as the default so the variant still shows
# it, and typed so a caller can replace it without editing this module.
resource "aws_s3_bucket_lifecycle_configuration" "s3_bucket" {
  count = length(var.lifecycle_rules) > 0 ? 1 : 0

  bucket = aws_s3_bucket.s3_bucket.id

  dynamic "rule" {
    for_each = var.lifecycle_rules
    content {
      id     = rule.key
      status = rule.value.enabled ? "Enabled" : "Disabled"

      # Always present, even when the caller wants the whole bucket. A rule with no filter at all is
      # rejected by the provider, and an empty prefix is how "everything" is expressed.
      filter {
        prefix = rule.value.prefix
      }

      dynamic "transition" {
        for_each = rule.value.transition_days == null ? [] : [rule.value]
        content {
          days          = transition.value.transition_days
          storage_class = transition.value.transition_storage_class
        }
      }

      dynamic "expiration" {
        for_each = rule.value.expiration_days == null ? [] : [rule.value]
        content {
          days = expiration.value.expiration_days
        }
      }
    }
  }

  # Versioning changes how expiration behaves, and the provider warns when the two are configured in
  # the same apply without ordering.
  depends_on = [aws_s3_bucket_versioning.s3_bucket]
}
