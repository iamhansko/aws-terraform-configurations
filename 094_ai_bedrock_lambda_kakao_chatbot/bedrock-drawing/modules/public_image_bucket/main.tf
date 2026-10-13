# The bucket the drawing functions put generated images in, readable by anyone.
#
# Public on purpose, as the SAM template made it: the chat service is given a plain S3 URL to show the image,
# and fetches it without credentials. What is public is s3:GetObject on objects - not listing, not writing -
# so someone without the exact object name finds nothing.
#
# Three differences from the template. Ownership is BucketOwnerEnforced, so no object ACL can grant more than
# the policy says. Objects expire after expiration_days, where the template kept every image forever in a
# public bucket. And the policy waits for the public access block to be relaxed - the two are separate calls,
# and S3 rejects a public policy while BlockPublicPolicy is still in force, which the _monolithic conversion
# left to chance.
resource "aws_s3_bucket" "images" {
  bucket_prefix = var.bucket_prefix
  # Every object in it is written by a function, not by Terraform, so without this terraform destroy stops at
  # BucketNotEmpty.
  force_destroy = true
}
resource "aws_s3_bucket_ownership_controls" "images" {
  bucket = aws_s3_bucket.images.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}
# Only the two settings that would block a public bucket policy are relaxed. ACLs stay blocked, since the bucket
# uses none.
resource "aws_s3_bucket_public_access_block" "images" {
  bucket                  = aws_s3_bucket.images.id
  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = false
  restrict_public_buckets = false
}
resource "aws_s3_bucket_policy" "images" {
  bucket = aws_s3_bucket.images.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "PublicReadGetObject"
      Effect    = "Allow"
      Principal = "*"
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.images.arn}/*"
    }]
  })
  depends_on = [aws_s3_bucket_public_access_block.images]
}
resource "aws_s3_bucket_lifecycle_configuration" "images" {
  count  = var.expiration_days == null ? 0 : 1
  bucket = aws_s3_bucket.images.id
  rule {
    id     = "expire-generated-images"
    status = "Enabled"
    filter {}
    expiration {
      days = var.expiration_days
    }
  }
}
