# The GitHub side of the pipeline: a CodeStar connection, the CodeBuild source credential, the token in
# Parameter Store and the bucket the seeded repository zip is uploaded to.
#
# Two things here need a human after the apply, and neither of them fails:
#   - a CodeStar connection is created in PENDING and only becomes AVAILABLE once someone completes the
#     GitHub handshake in the console. Terraform reports success either way, so connection_status is an
#     output and the root carries a check block that says so out loud.
#   - the source credential is account-and-region global for a given server type. A second copy of this
#     project in the same account overwrites the first one's token rather than failing.
resource "aws_codestarconnections_connection" "github" {
  name          = var.connection_name
  provider_type = "GitHub"
}
# What CodeBuild actually authenticates to GitHub with. The _monolithic template's CodeBuild project also
# carried a source auth block naming the connection above:
#
#   auth { type = "OAUTH", resource = aws_codestarconnections_connection.git_hub_connection.id }
#
# That block is deprecated in the AWS provider in favour of this resource, and it is this resource that the
# project picks up - one credential per (auth_type, server_type) applies to every CodeBuild project in the
# region. So the connection is scaffolding: it is created, it is surfaced, and nothing consumes it.
resource "aws_codebuild_source_credential" "github" {
  auth_type   = "PERSONAL_ACCESS_TOKEN"
  server_type = "GITHUB"
  token       = var.github_token
  user_name   = var.github_user
}
# The token again, in Parameter Store, so the association that pushes the seed commit can read it at
# runtime.
#
# The alternative is what the _monolithic template did - interpolate the token straight into the
# association's command:
#
#   git remote add origin https://${var.git_hub_token}@github.com/${var.git_hub_user}/${var.git_hub_repo}.git
#
# which puts a GitHub personal access token in two durable places that have nothing to do with Terraform
# state: the SSM document, readable forever by anyone with ssm:DescribeAssociation, and .git/config on an
# instance whose editor is served without authentication. Marking the variable sensitive does not touch
# either of them. Reading it from here instead means the token appears in state and in this parameter, and
# the association's command contains an aws ssm get-parameter call.
resource "aws_ssm_parameter" "github_token" {
  name        = var.token_parameter_name
  description = "GitHub personal access token the seed-commit association reads, so the token is not baked into the association document"
  type        = "SecureString"
  value       = var.github_token
}
# force_destroy so terraform destroy removes the bucket with the uploaded zip still in it. Without it the
# destroy fails on a non-empty bucket, which is a poor trade for an artefact that is regenerated on every
# apply.
#
# bucket_prefix rather than a name. The _monolithic template bought uniqueness by slicing a segment out of
# the uuid it generated to stand in for AWS::StackId; this is the provider's own way of getting it, and S3
# bucket names are globally unique rather than only account-unique, so it matters more here than anywhere
# else in this project.
resource "aws_s3_bucket" "source" {
  bucket_prefix = var.bucket_prefix
  force_destroy = var.force_destroy
}
# The bucket holds a zip of a sample repository, so nothing in it should be world-readable. The
# _monolithic template relied on the account default, which is safe on current accounts but says nothing
# about intent.
resource "aws_s3_bucket_public_access_block" "source" {
  bucket                  = aws_s3_bucket.source.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
resource "aws_s3_bucket_server_side_encryption_configuration" "source" {
  bucket = aws_s3_bucket.source.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
