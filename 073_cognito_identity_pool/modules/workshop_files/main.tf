# The workshop's source tree, staged in S3 so the workbench can copy it down in one command.
#
# The _monolithic template carried the same tree as 27 KB of echo '...' > file and cat << 'EOJS' statements
# inside a single SSM command string: HTML, JavaScript, package.json and two SAM templates, each quoted for
# the shell and then escaped again for HCL. Here every file is a file in the repository, readable and
# diffable, and the instance gets them with aws s3 sync - nothing passes through a shell quote.
#
# Four places differ from that tree. cognito-web/template.yaml is gone, because the web app it described is
# Terraform resources (modules/cognito_web_app); cognito-web/deploy.sh is new, and does what sam build and
# sam deploy did; web-ui-js/package.json pins the AWS SDK, for the reason deploy.sh gives; and the sign-up in
# web-ui-js/cognito-sdk.js reports its failures and can resend a code, where it put up the code prompt even
# when the sign-up had failed and nothing had been sent (its comment has the details, and
# public/cognito-sdk.html carries the Resend Code button it needs).
resource "aws_s3_bucket" "files" {
  bucket_prefix = var.bucket_prefix
  force_destroy = true
}
resource "aws_s3_bucket_public_access_block" "files" {
  bucket                  = aws_s3_bucket.files.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
resource "aws_s3_bucket_ownership_controls" "files" {
  bucket = aws_s3_bucket.files.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}
locals {
  files = fileset(var.source_dir, "**")
}
# fileset() reads the directory at plan, so the keys are known even though the bucket is not (rules.md B-8).
resource "aws_s3_object" "file" {
  for_each    = local.files
  bucket      = aws_s3_bucket.files.id
  key         = "${var.key_prefix}/${each.value}"
  source      = "${var.source_dir}/${each.value}"
  source_hash = filemd5("${var.source_dir}/${each.value}")
  depends_on  = [aws_s3_bucket_ownership_controls.files]
}
