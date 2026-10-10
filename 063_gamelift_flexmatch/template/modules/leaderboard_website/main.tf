# The leaderboard page. Public on purpose: it is an S3 static website, and website endpoints serve only what an
# anonymous principal can read. The only thing exposed is web/ from the game sample, with the API URL written
# into main.js by the root's client_config association.
resource "aws_s3_bucket" "web_bucket" {
  bucket_prefix = var.bucket_prefix
  force_destroy = var.force_destroy
}
resource "aws_s3_bucket_website_configuration" "web_bucket_website" {
  bucket = aws_s3_bucket.web_bucket.id
  index_document {
    suffix = var.index_document
  }
}
resource "aws_s3_bucket_public_access_block" "web_bucket_public_access_block" {
  bucket                  = aws_s3_bucket.web_bucket.id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}
resource "aws_s3_bucket_policy" "web_bucket_policy" {
  bucket = aws_s3_bucket.web_bucket.id
  policy = jsonencode({
    Id      = "WebS3BucketPolicy"
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = "*"
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.web_bucket.arn}/*"
    }]
  })
  # A new bucket starts with BlockPublicPolicy on, and PutBucketPolicy with a public principal is rejected with
  # AccessDenied until the block above has been lifted. Nothing in this policy references that resource, so the
  # order has to be stated (rules.md D-1). An account-level public access block overrides both and cannot be
  # lifted from here - in that account this resource fails whatever the order.
  depends_on = [aws_s3_bucket_public_access_block.web_bucket_public_access_block]
}
