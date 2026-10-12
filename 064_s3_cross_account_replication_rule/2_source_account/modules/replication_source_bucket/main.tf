# The bucket objects are replicated out of, and the rule that does it.
#
# The bucket and its replication configuration are one module because they are one thing: a replication
# configuration is a sub-resource of a bucket, there can be exactly one, and it is meaningless without it.
# Splitting them would give the caller two modules that must always appear together (rules.md C-2).
resource "aws_s3_bucket" "source" {
  bucket_prefix = var.name_prefix
  force_destroy = var.force_destroy
}
# Not optional. S3 refuses a replication configuration on a bucket without versioning, and this is the
# resource the configuration below has to wait for.
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
      # AES256 rather than KMS. A KMS-encrypted source needs the replication role granted kms:Decrypt on the
      # source key and kms:Encrypt on the destination key, in two accounts, and the replication configuration
      # needs source_selection_criteria to opt in - four more things to get wrong for a demo.
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
resource "aws_s3_bucket_ownership_controls" "source" {
  bucket = aws_s3_bucket.source.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}
resource "aws_s3_bucket_lifecycle_configuration" "source" {
  count  = var.noncurrent_version_expiration_days == null ? 0 : 1
  bucket = aws_s3_bucket.source.id

  rule {
    id     = "expire-noncurrent-source-versions"
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
resource "aws_s3_bucket_replication_configuration" "source" {
  bucket = aws_s3_bucket.source.id
  role   = var.replication_role_arn

  rule {
    # Named, where the _monolithic template left it generated. The id appears in every object's replication
    # status and in the CloudWatch metrics, and "rule-1" there tells you nothing.
    id       = "replicate-to-destination-account"
    status   = "Enabled"
    priority = 0

    # A filter block, even an empty-prefix one, is what makes this a V2 configuration - which is what
    # delete_marker_replication requires. Without the filter, S3 reads the rule as V1 and rejects the
    # delete marker setting.
    filter {
      prefix = var.rule_prefix
    }

    delete_marker_replication {
      status = var.replicate_delete_markers ? "Enabled" : "Disabled"
    }

    destination {
      bucket = var.destination_bucket_arn
      # Required for a cross-account rule, and it is a real check rather than a formality: without it S3
      # would replicate into any bucket named, and the owner of that bucket would have no say.
      account = var.destination_account_id

      # The half of ownership translation that lives here. The destination bucket's policy has to allow
      # s3:ObjectOwnerOverrideToBucketOwner as well, and the role has to be granted it - three settings that
      # only work together. The _monolithic template granted the action to the role and asked for no
      # translation, so the permission was unused and every replica stayed owned by this account.
      dynamic "access_control_translation" {
        for_each = var.replicate_owner_override ? [1] : []
        content {
          owner = "Destination"
        }
      }

      # Replication Time Control, off by default here where the original had it on. It is billed per
      # gigabyte replicated on top of the transfer, and turning it on also turns on the metrics - so the two
      # blocks move together rather than being independent switches.
      dynamic "replication_time" {
        for_each = var.replication_time_minutes == null ? [] : [var.replication_time_minutes]
        content {
          status = "Enabled"
          time {
            minutes = replication_time.value
          }
        }
      }
      dynamic "metrics" {
        for_each = var.replication_time_minutes == null ? [] : [var.replication_time_minutes]
        content {
          status = "Enabled"
          event_threshold {
            minutes = metrics.value
          }
        }
      }
    }
  }

  # Versioning has to exist first - S3 rejects the configuration otherwise - and referencing the bucket id
  # only orders this after the bucket (rules.md D-1).
  depends_on = [aws_s3_bucket_versioning.source]
}
resource "aws_s3_object" "demo" {
  for_each = var.objects

  bucket  = aws_s3_bucket.source.id
  key     = each.key
  content = each.value
  etag    = md5(each.value)

  # Written after the rule exists, because replication applies to objects created after the configuration.
  # An object uploaded first is simply never replicated, which looks like a broken rule - and the fix is to
  # upload it again, not to change anything here.
  depends_on = [aws_s3_bucket_replication_configuration.source]
}
