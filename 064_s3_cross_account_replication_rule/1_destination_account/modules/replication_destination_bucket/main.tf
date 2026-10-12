locals {
  # Built rather than passed in, so the policy and the name the source root agreed on cannot be two
  # different strings (rules.md I-2).
  replication_role_arn = "arn:aws:iam::${var.source_account_id}:role/${var.replication_role_name}"
}
# The bucket replicated objects arrive in.
#
# The _monolithic template was "resource aws_s3_bucket {}" plus a versioning block and a policy. Versioning
# is not optional - S3 refuses to replicate into a bucket without it - and the rest below is added.
resource "aws_s3_bucket" "destination" {
  bucket_prefix = var.name_prefix
  force_destroy = var.force_destroy
}
resource "aws_s3_bucket_versioning" "destination" {
  bucket = aws_s3_bucket.destination.id
  versioning_configuration {
    status = "Enabled"
  }
}
resource "aws_s3_bucket_server_side_encryption_configuration" "destination" {
  bucket = aws_s3_bucket.destination.id
  rule {
    apply_server_side_encryption_by_default {
      # AES256 rather than a KMS key. A KMS-encrypted destination needs the replication role granted
      # kms:Encrypt on that key in this account as well, which is a second cross-account grant and a second
      # thing to get wrong - worth doing deliberately, not by default.
      sse_algorithm = "AES256"
    }
  }
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
    # Enforced, so ACLs play no part. This is also why allow_owner_override matters: with ownership enforced
    # the replicated object still records the source account as its owner unless the replication asks for the
    # translation, and then nothing in this account can read it.
    object_ownership = "BucketOwnerEnforced"
  }
}
resource "aws_s3_bucket_lifecycle_configuration" "destination" {
  count  = var.noncurrent_version_expiration_days == null ? 0 : 1
  bucket = aws_s3_bucket.destination.id

  rule {
    id     = "expire-noncurrent-replicated-versions"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_expiration_days
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.destination]
}
# What lets the source account's replication role write here.
#
# Split by resource level rather than granting every action on both ARNs, which is what the _monolithic
# template did: it listed GetBucketVersioning, PutBucketVersioning, ReplicateObject and ReplicateDelete
# against the bucket and everything in it, so half the actions were granted on a resource they cannot apply
# to. Harmless, but it hides which permission is for what.
resource "aws_s3_bucket_policy" "destination" {
  bucket = aws_s3_bucket.destination.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowReplicationRoleToReadBucketConfiguration"
        Effect = "Allow"
        # S3 validates an explicit role principal when the policy is saved, but this destination root must be
        # applied before that role exists in the source account. The account root is always valid, while the
        # PrincipalArn condition narrows effective access back to the one agreed role ARN. The role also needs
        # its own identity policy, so this does not delegate access to other principals in that account
        # (rules.md I-2).
        Principal = { AWS = "arn:aws:iam::${var.source_account_id}:root" }
        Condition = {
          ArnEquals = {
            "aws:PrincipalArn" = local.replication_role_arn
          }
        }
        Action   = ["s3:GetBucketVersioning", "s3:PutBucketVersioning", "s3:ListBucket"]
        Resource = aws_s3_bucket.destination.arn
      },
      {
        Sid       = "AllowReplicationRoleToReplicateObjects"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${var.source_account_id}:root" }
        Condition = {
          ArnEquals = {
            "aws:PrincipalArn" = local.replication_role_arn
          }
        }
        Action = concat(
          ["s3:ReplicateObject", "s3:ReplicateDelete", "s3:ReplicateTags", "s3:GetObjectVersionTagging"],
          # Without this the source's access_control_translation fails and replication stops with an access
          # denied that appears only in the replication status of the objects, not in any log here.
          var.allow_owner_override ? ["s3:ObjectOwnerOverrideToBucketOwner"] : [],
        )
        Resource = "${aws_s3_bucket.destination.arn}/*"
      },
    ]
  })

  # block_public_policy is on, and this policy is limited to one account and then one role ARN, so it is not
  # public. The setting still has to be in place before the policy is evaluated. Referencing the bucket id
  # orders this after the bucket only (rules.md D-1).
  depends_on = [aws_s3_bucket_public_access_block.destination]
}
