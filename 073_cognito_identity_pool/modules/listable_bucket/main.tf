# The bucket the workshop page lists through identity pool credentials, with the two sample objects it lists.
resource "aws_s3_bucket" "bucket" {
  bucket_prefix = var.bucket_prefix
  force_destroy = var.force_destroy
}
resource "aws_s3_bucket_public_access_block" "bucket" {
  bucket                  = aws_s3_bucket.bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
# The browser calls ListObjectsV2 directly from the web app's origin, which S3 refuses without CORS.
resource "aws_s3_bucket_cors_configuration" "bucket" {
  bucket = aws_s3_bucket.bucket.id
  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET"]
    allowed_origins = var.cors_allowed_origins
    expose_headers  = []
  }
}
# The objects the _monolithic template's second stage wrote with echo and aws s3 cp from the workbench. Keyed
# by object key, which is configuration (rules.md B-8).
resource "aws_s3_object" "sample" {
  for_each     = var.sample_objects
  bucket       = aws_s3_bucket.bucket.id
  key          = each.key
  content      = each.value
  content_type = "text/plain"
}
