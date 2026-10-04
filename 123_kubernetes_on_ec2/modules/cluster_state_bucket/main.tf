# The bucket the three instances hand files through: the control plane writes the
# admin kubeconfig and a kubeadm join command into it, and the worker and the
# workbench read them back out. There is no control-plane API to ask for either
# before the cluster exists, so a bucket is the handoff.
#
# bucket_prefix rather than a fixed name, so two copies of this project in one
# account do not collide on a globally unique name.
resource "aws_s3_bucket" "cluster_state" {
  bucket_prefix = var.bucket_prefix
  # This one argument replaces the entire custom resource the _monolithic template
  # carried: a Python Lambda, its IAM role, two managed policy attachments, an
  # archive_file and an aws_lambda_invocation, all to empty the bucket so the stack
  # could be deleted. Terraform models that directly.
  #
  # The Lambda could not have worked in that form anyway - it began with
  # "import cfnresponse", a module CloudFormation injects into its own custom
  # resource runtime and which does not exist in a plain Lambda deployment package,
  # so the handler would have failed on import.
  force_destroy = var.force_destroy
  tags = {
    Name = var.name
  }
}
# The kubeconfig in this bucket is a cluster-admin credential. Nothing here should be
# reachable from outside the account, and none of it is public by default - but a
# bucket holding an admin credential is worth blocking explicitly rather than
# relying on the account-level default staying on.
resource "aws_s3_bucket_public_access_block" "cluster_state" {
  bucket                  = aws_s3_bucket.cluster_state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
resource "aws_s3_bucket_ownership_controls" "cluster_state" {
  bucket = aws_s3_bucket.cluster_state.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}
# Server-side encryption with the S3 managed key. The _monolithic template's bucket
# had no encryption configuration at all, which left the admin kubeconfig at rest
# under whatever the account default happened to be.
resource "aws_s3_bucket_server_side_encryption_configuration" "cluster_state" {
  bucket = aws_s3_bucket.cluster_state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = var.sse_algorithm
    }
  }
}
# Scoped to this bucket, unlike the _monolithic template, which gave all three
# instance roles AmazonS3FullAccess - account-wide read and write on every bucket,
# for two files. The policy is produced here and attached by the caller, because the
# roles belong to the instance modules (rules.md B-6).
resource "aws_iam_policy" "cluster_state_access" {
  name_prefix = var.policy_name_prefix
  description = "Read and write the kubeadm handoff objects in one bucket"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = aws_s3_bucket.cluster_state.arn
      },
      {
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        # Only the objects this project actually exchanges. A wildcard here would be
        # no worse in practice - the bucket holds nothing else - but naming them
        # documents the protocol between the three instances.
        Resource = [for key in var.object_keys : "${aws_s3_bucket.cluster_state.arn}/${key}"]
      },
    ]
  })
}
