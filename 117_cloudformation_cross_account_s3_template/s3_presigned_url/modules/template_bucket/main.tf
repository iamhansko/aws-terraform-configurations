# A private bucket with one CloudFormation template in it.
#
# Unlike the bucket account root's bucket there is no bucket policy: nothing outside this account reads it
# by identity. The presigned URL is what grants the read, and it carries the signer's own permissions with
# it - so the bucket stays fully private and the URL still works.
resource "aws_s3_bucket" "templates" {
  bucket_prefix = var.bucket_prefix
  # The template object is Terraform's and is deleted before the bucket. The README walks through uploading
  # the same file again from the workbench, which leaves an object Terraform does not know about - without
  # this, that one copy is enough to stop terraform destroy at BucketNotEmpty.
  force_destroy = var.force_destroy
}
resource "aws_s3_bucket_public_access_block" "templates" {
  bucket                  = aws_s3_bucket.templates.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
resource "aws_s3_bucket_ownership_controls" "templates" {
  bucket = aws_s3_bucket.templates.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}
resource "aws_s3_object" "template" {
  bucket       = aws_s3_bucket.templates.id
  key          = var.template_key
  content      = var.template_body
  content_type = "application/x-yaml"
  depends_on   = [aws_s3_bucket_ownership_controls.templates]
}
