# Where Teleport writes session recordings.
#
# The _monolithic template declared this as a bare aws_s3_bucket with an empty body: no
# versioning, no encryption, no public access block, no lifecycle. Everything below is
# what that leaves out, and none of it is optional for what the bucket holds - a session
# recording is a keystroke-level transcript of an operator working on a production system.
#
# The template's approach was to grant the writer s3:PutBucketVersioning and
# s3:PutEncryptionConfiguration and let Teleport configure the bucket on first use. That
# works, and it means a property of infrastructure Terraform owns is set by something
# outside Terraform - so plan shows nothing, and a bucket whose configuration drifted
# looks identical to one that never had it.
resource "aws_s3_bucket" "teleport_session_bucket" {
  bucket        = var.name
  bucket_prefix = var.name == null ? var.name_prefix : null
  force_destroy = var.force_destroy
}
# Required by Teleport rather than merely advisable. See var.versioning_enabled.
resource "aws_s3_bucket_versioning" "teleport_session_bucket" {
  bucket = aws_s3_bucket.teleport_session_bucket.id
  versioning_configuration {
    status = var.versioning_enabled ? "Enabled" : "Suspended"
  }
}
resource "aws_s3_bucket_server_side_encryption_configuration" "teleport_session_bucket" {
  bucket = aws_s3_bucket.teleport_session_bucket.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.sse_algorithm
      kms_master_key_id = var.kms_key_arn
    }
    # Only meaningful with KMS, where it lets S3 use one data key for many objects instead
    # of calling KMS per object. Harmless otherwise, and a recording is written as many
    # small parts, so the call volume is the thing being reduced.
    bucket_key_enabled = var.sse_algorithm == "aws:kms"
  }
}
# Nothing should reach these objects except Teleport. This blocks the four ways a bucket
# becomes public by accident, independently of any policy that might be attached later.
resource "aws_s3_bucket_public_access_block" "teleport_session_bucket" {
  bucket                  = aws_s3_bucket.teleport_session_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
# Bucket-owner-enforced, which disables ACLs entirely. Teleport addresses objects through
# the bucket's own identity, so there is no cross-account grant to preserve - and with ACLs
# off, "who can read this" is answered by the bucket policy alone.
resource "aws_s3_bucket_ownership_controls" "teleport_session_bucket" {
  bucket = aws_s3_bucket.teleport_session_bucket.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}
# Versioning is mandatory here, so every overwrite leaves a version behind. Without this
# the bucket grows without bound, and deleted recordings keep both their cost and their
# contents.
resource "aws_s3_bucket_lifecycle_configuration" "teleport_session_bucket" {
  count = var.noncurrent_version_expiration_days > 0 ? 1 : 0

  bucket = aws_s3_bucket.teleport_session_bucket.id
  rule {
    id     = "expire-noncurrent-versions"
    status = "Enabled"
    # An empty filter means the whole bucket. The provider requires the block to be
    # present even when it selects everything.
    filter {}
    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_expiration_days
    }
    # Multipart uploads that never completed are invisible in a bucket listing and billed
    # anyway. A recording is uploaded in parts, so an auth pod killed mid-session leaves
    # one behind.
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  # A lifecycle rule that touches versions needs versioning to exist first; the bucket ID
  # alone does not order this after the versioning resource (rules.md D-1).
  depends_on = [aws_s3_bucket_versioning.teleport_session_bucket]
}
