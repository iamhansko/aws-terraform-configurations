# The GitHub side of the demo: a CodeStar connection, a CodeBuild source credential and an S3
# bucket that the seed repository is uploaded to.
#
# Carried over from the _monolithic template as-is, but worth being honest about what it is.
# Nothing in this project consumes any of it: there is no CodeBuild project and no pipeline, and
# Argo CD reads the repository over https from github.com rather than from this bucket. It is
# scaffolding for a CI half that was never finished.
#
# Two things about it need a human after the apply:
#   - a CodeStar connection is created in PENDING and only becomes AVAILABLE once someone
#     completes the GitHub handshake in the console. Terraform reports success either way, so
#     connection_status is exposed as an output rather than left to be discovered.
#   - the source credential is account-and-region global for a given server type. A second copy
#     of this project in the same account overwrites the first one's token rather than failing.
resource "aws_codestarconnections_connection" "github" {
  name          = var.connection_name
  provider_type = "GitHub"
}
resource "aws_codebuild_source_credential" "github" {
  auth_type   = "PERSONAL_ACCESS_TOKEN"
  server_type = "GITHUB"
  token       = var.github_token
  user_name   = var.github_user
}
# force_destroy so terraform destroy removes the bucket with the uploaded zip still in it.
# Without it the destroy fails on a non-empty bucket, which is a poor trade for a demo artifact
# that is regenerated on every apply.
resource "aws_s3_bucket" "source" {
  bucket        = var.bucket_name
  force_destroy = var.force_destroy
}
# The bucket holds a zip of a sample repository, so nothing here should be world-readable. The
# _monolithic template relied on the account default, which is safe on current accounts but says
# nothing about intent.
resource "aws_s3_bucket_public_access_block" "source" {
  bucket                  = aws_s3_bucket.source.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
resource "aws_s3_bucket_versioning" "source" {
  bucket = aws_s3_bucket.source.id
  versioning_configuration {
    status = var.versioning_enabled ? "Enabled" : "Suspended"
  }
}
# The seed repository is re-uploaded on every apply, so old versions accumulate with nothing
# reading them. This expires them rather than leaving the bucket to grow.
resource "aws_s3_bucket_lifecycle_configuration" "source" {
  count  = var.versioning_enabled ? 1 : 0
  bucket = aws_s3_bucket.source.id

  rule {
    id     = "expire-noncurrent-versions"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_expiration_days
    }
  }

  depends_on = [aws_s3_bucket_versioning.source]
}
