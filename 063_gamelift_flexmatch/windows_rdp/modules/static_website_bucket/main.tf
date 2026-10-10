# The leaderboard page: index.html and a main.js that the userdata patches with
# this deployment's API id, region and stage before uploading. Public by design -
# an S3 website endpoint serves anonymous requests only, so a bucket a browser
# cannot read anonymously has no website.
resource "aws_s3_bucket" "website" {
  bucket_prefix = var.bucket_prefix

  # The page files are uploaded from the instance and are not in state, so
  # destroy would otherwise stop at BucketNotEmpty.
  force_destroy = var.force_destroy
}
resource "aws_s3_bucket_website_configuration" "website" {
  bucket = aws_s3_bucket.website.id
  index_document {
    suffix = var.index_document
  }
}
# All four off, as the _monolithic template had it. BlockPublicPolicy is the one
# that matters: it is on by default for every new bucket, and while it is on S3
# rejects the bucket policy below with AccessDenied because that policy grants
# to "*".
resource "aws_s3_bucket_public_access_block" "website" {
  bucket                  = aws_s3_bucket.website.id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}
resource "aws_s3_bucket_policy" "website" {
  bucket = aws_s3_bucket.website.id
  policy = jsonencode({
    Id      = "WebS3BucketPolicy"
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = "*"
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.website.arn}/*"
    }]
  })

  # Both resources reference only the bucket, so nothing else orders this after
  # the block is lifted, and PutBucketPolicy with a public principal is refused
  # while BlockPublicPolicy is still in force (rules.md D-1). The conversion had
  # no such edge and would have raced it.
  depends_on = [aws_s3_bucket_public_access_block.website]
}
