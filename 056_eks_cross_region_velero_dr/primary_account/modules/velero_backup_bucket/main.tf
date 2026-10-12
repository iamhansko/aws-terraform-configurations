# The S3 bucket Velero writes backups to.
#
# The _monolithic template's version of this was one line - resource "aws_s3_bucket" "s3_bucket" {}
# - plus a separate versioning resource. Everything below it is what that line left out, and most of
# it matters in ways that only show up later:
#
#   - No encryption. Kubernetes backups contain every Secret in the cluster, in plaintext inside the
#     backup tarball.
#   - No public access block. The bucket is private by default, but nothing stops a later bucket
#     policy or ACL from opening it.
#   - No lifecycle rule for incomplete multipart uploads. Velero uploads backups in parts, and a
#     failed or cancelled backup leaves those parts billable and invisible - they do not appear in
#     the object listing.
#   - No force_destroy. Velero's backups are objects Terraform did not create, so terraform destroy
#     fails with BucketNotEmpty and leaves the bucket behind (rules.md I-4).
#
# Versioning is not optional here: S3 replication requires it on both the source and the
# destination, so the cross-account variants cannot work without it. It is also what makes
# force_destroy destructive beyond recovery, since the versions go too.
resource "aws_s3_bucket" "velero_backup_bucket" {
  bucket        = var.bucket_name
  bucket_prefix = var.bucket_name == null ? var.bucket_name_prefix : null
  # Deliberate and explicit rather than left at its default. Velero's backups are objects no apply
  # created, so with this false a destroy fails on a non-empty bucket; with it true the backups are
  # deleted along with the bucket, and because versioning is on, every version goes with them
  # (rules.md I-4).
  force_destroy = var.force_destroy
}
# Required by S3 replication on both ends, and the reason this is not optional. It also means a
# backup Velero overwrites keeps its previous version, which is the only thing standing between a
# corrupted backup and no backup at all.
resource "aws_s3_bucket_versioning" "velero_backup_bucket" {
  bucket = aws_s3_bucket.velero_backup_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}
# A Kubernetes backup contains every Secret in the cluster. SSE-S3 rather than a customer KMS key,
# which would also need a key policy admitting the Velero role in this account and - for the
# cross-account variants - the replication role and the destination account.
resource "aws_s3_bucket_server_side_encryption_configuration" "velero_backup_bucket" {
  bucket = aws_s3_bucket.velero_backup_bucket.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}
resource "aws_s3_bucket_public_access_block" "velero_backup_bucket" {
  bucket                  = aws_s3_bucket.velero_backup_bucket.id
  block_public_acls       = true
  block_public_policy     = var.block_public_policy
  ignore_public_acls      = true
  restrict_public_buckets = true
}
# Ownership enforced, so ACLs cannot grant anything. This matters for the cross-account case
# specifically: with BucketOwnerEnforced the destination account owns every replicated object
# outright, rather than the source account owning objects sitting in someone else's bucket - which
# is what makes them readable by the destination cluster's Velero at all.
resource "aws_s3_bucket_ownership_controls" "velero_backup_bucket" {
  bucket = aws_s3_bucket.velero_backup_bucket.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}
# Incomplete multipart uploads are the invisible cost of a backup tool. Velero uploads in parts, an
# interrupted backup leaves them, and they are billed while appearing in no object listing. The
# _monolithic template had no lifecycle configuration at all.
resource "aws_s3_bucket_lifecycle_configuration" "velero_backup_bucket" {
  bucket = aws_s3_bucket.velero_backup_bucket.id

  rule {
    id     = "abort-incomplete-multipart-uploads"
    status = "Enabled"
    filter {}
    abort_incomplete_multipart_upload {
      days_after_initiation = var.abort_incomplete_multipart_upload_days
    }
  }

  dynamic "rule" {
    for_each = var.noncurrent_version_expiration_days == null ? [] : [1]

    content {
      id     = "expire-noncurrent-versions"
      status = "Enabled"
      filter {}
      noncurrent_version_expiration {
        noncurrent_days = var.noncurrent_version_expiration_days
      }
    }
  }

  # Versioning has to be on before a noncurrent-version rule is accepted, and the bucket ID
  # reference does not order this after it (rules.md D-1).
  depends_on = [aws_s3_bucket_versioning.velero_backup_bucket]
}
# Only on the receiving side of a cross-account replication. The source account's replication role
# is a principal in another account, so it can only be granted access by a policy on this bucket -
# there is no other place to put it (rules.md I-2).
#
# S3 validates a role named directly as Principal when PutBucketPolicy runs and rejects the policy
# with "Invalid principal" if that role does not exist yet. The destination root has to apply first,
# so use each source account's always-existing root principal and narrow it back to the agreed role
# ARN with aws:PrincipalArn. The condition preserves least privilege while breaking the cross-state
# bootstrap cycle.
locals {
  replication_source_account_root_arns = distinct([
    for arn in var.replication_source_role_arns : "arn:aws:iam::${split(":", arn)[4]}:root"
  ])
}
resource "aws_s3_bucket_policy" "velero_backup_bucket" {
  count = length(var.replication_source_role_arns) > 0 ? 1 : 0

  bucket = aws_s3_bucket.velero_backup_bucket.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowReplicationFromSourceRoles"
        Effect = "Allow"
        Principal = {
          AWS = local.replication_source_account_root_arns
        }
        Condition = {
          ArnEquals = {
            "aws:PrincipalArn" = var.replication_source_role_arns
          }
        }
        Action = [
          "s3:ReplicateObject",
          "s3:ReplicateDelete",
          # ReplicateTags was missing from the _monolithic template's policy while the source's
          # replication role was granted it. Velero tags its objects, so without this the tags are
          # dropped on the copy and a restore in the destination cluster reads a backup whose
          # metadata does not match the source's.
          "s3:ReplicateTags",
          "s3:ObjectOwnerOverrideToBucketOwner",
        ]
        Resource = "${aws_s3_bucket.velero_backup_bucket.arn}/*"
      },
      {
        Sid    = "AllowReplicationConfigurationReadsFromSourceRoles"
        Effect = "Allow"
        Principal = {
          AWS = local.replication_source_account_root_arns
        }
        Condition = {
          ArnEquals = {
            "aws:PrincipalArn" = var.replication_source_role_arns
          }
        }
        Action = [
          "s3:GetBucketVersioning",
          "s3:PutBucketVersioning",
          "s3:List*",
        ]
        Resource = aws_s3_bucket.velero_backup_bucket.arn
      },
      {
        Sid       = "DenyUnencryptedTransport"
        Effect    = "Deny"
        Action    = "s3:*"
        Resource  = [aws_s3_bucket.velero_backup_bucket.arn, "${aws_s3_bucket.velero_backup_bucket.arn}/*"]
        Principal = "*"
        Condition = {
          Bool = {
            "aws:SecureTransport" = false
          }
        }
      },
    ]
  })

  # A bucket policy is rejected while BlockPublicPolicy is being evaluated against a policy that
  # names a wildcard principal, and the ownership controls decide whether the ACL statements are
  # accepted at all. Neither is implied by the bucket ID reference (rules.md D-1).
  depends_on = [
    aws_s3_bucket_public_access_block.velero_backup_bucket,
    aws_s3_bucket_ownership_controls.velero_backup_bucket,
  ]
}
