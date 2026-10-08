# Where the exported certificate and its private key are left for whoever is running the demo.
#
# This bucket holds an unencrypted RSA private key and the certificate that goes with it, which is
# everything needed to obtain the vended role's credentials. For the length of the demo it is a
# secret store, and the three resources after the bucket are here because of that - the
# _monolithic template declared the bucket and nothing else.
resource "aws_s3_bucket" "artifacts" {
  # bucket_prefix rather than a fixed name, and rather than the _monolithic template's nothing at
  # all. Bucket names are globally unique, so a literal collides with a second copy of this project
  # and with every other account in the world; leaving it unset works but produces
  # terraform-20240101000000000000000001, which says nothing about what is in it.
  bucket_prefix = var.bucket_prefix
  # The bootstrap writes four objects that Terraform did not create, so a destroy without this
  # stops on BucketNotEmpty. Deleting them with the bucket is the point rather than a cost: one of
  # them is the unencrypted private key, and the bucket is the only copy of it.
  force_destroy = var.force_destroy
}
# Not in the _monolithic template. New buckets have blocked public access by default, so this
# changes nothing today - it is here to say so in the plan and to keep saying it if an account's
# defaults are ever different. For a bucket whose contents are a usable AWS credential, "public
# access is blocked" should be a line someone can point at rather than an assumption.
resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket                  = aws_s3_bucket.artifacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
# Also not in the _monolithic template, and the same reasoning. SSE-S3 is the default for new
# objects; declaring it means the bucket cannot quietly end up without it.
#
# Worth being honest about what this does and does not buy: it encrypts the key at rest against
# someone reading the disks, and it does nothing at all against anyone who can call GetObject.
# Nothing here is protecting the key from an over-broad IAM policy - only destroying the bucket is.
resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = var.sse_algorithm
    }
  }
}
# Object ownership enforced, so the bucket has no ACLs and the only thing granting access is IAM.
# The bootstrap uploads with put-object and passes no ACL, so this takes nothing away from it.
resource "aws_s3_bucket_ownership_controls" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}
