# The bucket the function writes its page into.
#
# The _monolithic template declared it as a bare aws_s3_bucket {}: a generated name, and everything else at the
# provider's defaults. Two of those defaults matter here. force_destroy defaults to false, and the function
# puts an object in this bucket that Terraform did not create, so the first terraform destroy after a single
# invocation stops at BucketNotEmpty. And the name was generated as "terraform-<timestamp>", which says nothing
# about what the bucket is for.
resource "aws_s3_bucket" "bucket" {
  bucket_prefix = var.bucket_prefix
  force_destroy = var.force_destroy
}
# Nothing in it is meant to be public - the page is read back with the CLI, not served. The account default is
# already this on current accounts; declaring it says the intent rather than relying on the default.
resource "aws_s3_bucket_public_access_block" "bucket" {
  bucket                  = aws_s3_bucket.bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
resource "aws_s3_bucket_server_side_encryption_configuration" "bucket" {
  bucket = aws_s3_bucket.bucket.id
  rule {
    apply_server_side_encryption_by_default {
      # SSE-S3 rather than KMS, so the function's role needs no key grant beyond s3:PutObject.
      sse_algorithm = "AES256"
    }
  }
}
