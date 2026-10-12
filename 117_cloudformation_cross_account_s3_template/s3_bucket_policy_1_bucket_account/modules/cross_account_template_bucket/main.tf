data "aws_region" "current" {}
# A bucket holding one CloudFormation template, readable from one other account.
#
# The bucket, its policy and the template object are one module because the policy is written for exactly
# this object's key space and the object is the only reason the bucket exists.
#
# bucket_prefix rather than a fixed name: the _monolithic template built
# "cloudformation-templates-<stack_name>-<uuid slice>" for the same uniqueness, with a random_uuid standing in
# for AWS::StackId.
resource "aws_s3_bucket" "templates" {
  bucket_prefix = var.bucket_prefix
  # The only object in here is the one below, which Terraform deletes itself before the bucket. This is for
  # anything a person copied in by hand while trying the demo.
  force_destroy = var.force_destroy
}
resource "aws_s3_bucket_public_access_block" "templates" {
  bucket                  = aws_s3_bucket.templates.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
# BucketOwnerEnforced, so ACLs play no part and the bucket policy below is the whole of the cross-account
# access story.
resource "aws_s3_bucket_ownership_controls" "templates" {
  bucket = aws_s3_bucket.templates.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}
# The cross-account grant, which is the subject of this project.
#
# The principal is the reading account's root - meaning "any principal in that account whose own IAM policy
# also allows it" - rather than the CloudFormation service role that account creates. That is deliberate:
# CloudFormation fetches a TemplateURL with the credentials of whoever calls CreateStack, not with the service
# role passed as --role-arn (AWS's troubleshooting guide for "S3 Access Denied" on CreateStack points at the
# calling identity's s3:GetObject), so a policy naming only the role would deny the fetch. The _monolithic template
# carried a cloud_formation_iam_role_name variable it never used, which reads like the remains of exactly that
# attempt.
#
# jsonencode rather than the heredoc JSON the _monolithic template interpolated into, so a value cannot break
# the document's quoting.
resource "aws_s3_bucket_policy" "templates" {
  bucket = aws_s3_bucket.templates.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowGetObject"
        Effect    = "Allow"
        Principal = { AWS = [for id in var.reader_account_ids : "arn:aws:iam::${id}:root"] }
        Action    = ["s3:GetObject", "s3:GetObjectVersion"]
        Resource  = "${aws_s3_bucket.templates.arn}/*"
      },
      {
        Sid       = "AllowGetBucketLocation"
        Effect    = "Allow"
        Principal = { AWS = [for id in var.reader_account_ids : "arn:aws:iam::${id}:root"] }
        Action    = "s3:GetBucketLocation"
        Resource  = aws_s3_bucket.templates.arn
      },
    ]
  })
  # S3 evaluates a new bucket policy against the public access block, and the two are separate API calls.
  # Nothing here is public, so this is about not racing the block rather than about passing it (rules.md D-1).
  depends_on = [aws_s3_bucket_public_access_block.templates]
}
resource "aws_s3_object" "template" {
  bucket = aws_s3_bucket.templates.id
  key    = var.template_key
  # content rather than source, so the module takes the template as a string and does not have to know where
  # the caller keeps it.
  content      = var.template_body
  content_type = "application/x-yaml"
  # Uploaded under BucketOwnerEnforced, so the object belongs to this account regardless of who wrote it.
  depends_on = [aws_s3_bucket_ownership_controls.templates]
}
