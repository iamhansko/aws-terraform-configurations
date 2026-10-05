# The bucket the three pods try to read, and the thing that makes the comparison concrete: an identity
# that cannot list it is an identity without the permission, whichever mechanism produced it.
#
# The _monolithic template declared this as "resource aws_s3_bucket s3_bucket {}" - no name, no
# encryption, no public access block, no ownership controls, and no objects in it. Everything below except
# the bucket itself is an addition, and each one is there for a reason rather than for completeness.
resource "aws_s3_bucket" "demo" {
  bucket        = var.bucket_name
  bucket_prefix = var.bucket_name == null ? var.bucket_name_prefix : null
  force_destroy = var.force_destroy
}
# S3 has not applied ACLs to new buckets for years, but the setting is still a bucket attribute and
# stating it is what makes "this bucket has no ACLs" a decision rather than a default that could change.
resource "aws_s3_bucket_ownership_controls" "demo" {
  bucket = aws_s3_bucket.demo.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}
# All four switches, explicitly. The account-level setting usually covers this, and relying on it means a
# bucket that is private in one account and public in another from the same configuration.
resource "aws_s3_bucket_public_access_block" "demo" {
  bucket                  = aws_s3_bucket.demo.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
resource "aws_s3_bucket_server_side_encryption_configuration" "demo" {
  bucket = aws_s3_bucket.demo.id
  rule {
    apply_server_side_encryption_by_default {
      # SSE-S3 rather than a KMS key. A KMS key would add a second thing each pod's identity needs
      # permission for, and "which identity can read the bucket" would stop being the only variable -
      # the IMDS pod would then fail on the key rather than on the bucket, which is a different lesson.
      sse_algorithm = "AES256"
    }
  }
}
# Something to list. Without an object, a successful "aws s3 ls" prints nothing - which is what a denied
# call that the CLI swallowed also looks like.
resource "aws_s3_object" "demo" {
  for_each = toset(var.object_keys)

  bucket  = aws_s3_bucket.demo.id
  key     = each.value
  content = "Written by Terraform so that listing this bucket from inside a pod prints something.\n"
  # Without this the provider sends no content type and S3 defaults to binary, so a browser downloads the
  # file rather than showing it.
  content_type = "text/plain"

  # The encryption configuration has to be in place before the first object, or that object is stored
  # under whatever default applied at the time and stays that way - object encryption is set at write
  # time, not by the bucket (rules.md D-1).
  depends_on = [aws_s3_bucket_server_side_encryption_configuration.demo]
}
