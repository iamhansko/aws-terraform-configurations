# A private bucket the Slack app stores its OAuth state or its installations in.
#
# The SAM template declared both as bare AWS::S3::Bucket resources and left everything else at S3's defaults,
# which today already block public access and enforce bucket ownership. Stated here so the plan shows it, and
# with force_destroy: Bolt writes both buckets at runtime, so without it terraform destroy stops at
# BucketNotEmpty.
#
# The installation bucket holds every workspace's bot token. Anyone who can read it can post as the app in
# each of those workspaces, which is why the function's policy names these two buckets and nothing wider.
resource "aws_s3_bucket" "bucket" {
  bucket_prefix = var.bucket_prefix
  force_destroy = true
}
resource "aws_s3_bucket_public_access_block" "bucket" {
  bucket                  = aws_s3_bucket.bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
resource "aws_s3_bucket_ownership_controls" "bucket" {
  bucket = aws_s3_bucket.bucket.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}
