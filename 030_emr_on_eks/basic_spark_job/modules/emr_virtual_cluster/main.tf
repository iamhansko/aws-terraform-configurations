data "aws_region" "current" {}

# The EMR on EKS virtual cluster, the role its jobs run as, and the two places a job writes.
#
# One module because they are one component: the virtual cluster is useless without a job
# execution role, the role's trust policy names the virtual cluster's namespace, and the bucket
# and log group exist only to be named in a job's monitoringConfiguration. That is the same
# reasoning that keeps a controller's IAM role next to its Helm release (rules.md C-2).
resource "aws_emrcontainers_virtual_cluster" "virtual_cluster" {
  name = var.name

  container_provider {
    id   = var.cluster_name
    type = "EKS"
    info {
      eks_info {
        namespace = var.namespace
      }
    }
  }
}

# The role a Spark job assumes, through IRSA rather than Pod Identity.
#
# IRSA here is not a leftover: EMR on EKS creates its own service accounts per job, named
# emr-containers-sa-<framework>-<component>-<account>-<base36 role name>, and it does not create
# Pod Identity associations for them. The trust policy therefore has to match a name it cannot
# know in advance, which is what the StringLike wildcard below is for - and what
# `aws emr-containers update-role-trust-policy` writes when done by hand.
resource "aws_iam_role" "job_execution" {
  name_prefix = "${substr(var.name, 0, 24)}-job-"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = var.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        # StringLike, not StringEquals: the service account name carries a base36 encoding of this
        # role's own name, so the exact value is not knowable here. Scoped to the one namespace,
        # which is what keeps the wildcard from meaning "any service account in the cluster".
        StringLike = {
          "${var.oidc_issuer_host}:sub" = "system:serviceaccount:${var.namespace}:emr-containers-sa-*"
        }
      }
    }]
  })
}

# Where a job reads its scripts and input and writes its output and logs.
#
# force_destroy, because a job puts objects in here that Terraform does not track and S3 refuses
# to delete a non-empty bucket. The _monolithic template declared a bare aws_s3_bucket with no
# name, no encryption, no public access block and no force_destroy - so a destroy stopped on it
# once a job had run.
resource "aws_s3_bucket" "job" {
  bucket_prefix = var.bucket_prefix
  force_destroy = var.force_destroy
  tags = {
    Name = "${var.name}-job-data"
  }
}

resource "aws_s3_bucket_public_access_block" "job" {
  bucket                  = aws_s3_bucket.job.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "job" {
  bucket = aws_s3_bucket.job.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "job" {
  bucket = aws_s3_bucket.job.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_cloudwatch_log_group" "job" {
  name              = var.log_group_name
  retention_in_days = var.log_retention_days
}

# Scoped to this bucket and this log group, where the _monolithic template's inline policy granted
# s3:PutObject, s3:GetObject and s3:ListBucket on "*" and log writes on every log group in the
# account. A Spark job runs arbitrary code from the bucket it can read, so what that role can
# reach is worth naming (rules.md A-5).
#
# One statement is the exception, and the comment on it explains why: logs:DescribeLogGroups has
# no resource to name. Scoping that one is what made every job run fail.
resource "aws_iam_role_policy" "job_execution" {
  name = "job-execution"
  role = aws_iam_role.job_execution.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket", "s3:GetBucketLocation"]
        Resource = aws_s3_bucket.job.arn
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = "${aws_s3_bucket.job.arn}/*"
      },
      {
        Effect = "Allow"
        Action = ["logs:PutLogEvents", "logs:CreateLogStream", "logs:DescribeLogStreams"]
        # The log group and its streams. These three do support resource-level permissions, so
        # they stay scoped to this one group - unlike DescribeLogGroups below.
        Resource = ["${aws_cloudwatch_log_group.job.arn}:*"]
      },
      {
        Effect = "Allow"
        Action = ["logs:DescribeLogGroups"]
        # "*", and it cannot be narrowed. DescribeLogGroups is a list operation over the account
        # and CloudWatch Logs does not support resource-level permissions for it, so IAM evaluates
        # it against "*" alone: a grant naming a log group ARN - this statement's previous form,
        # and the arn:aws:logs:*:*:* that AWS's own EMR on EKS documentation shows - authorises
        # nothing at all.
        #
        # Nothing reports that as a policy error. The job fails before any pod is created, with
        #
        #   stateDetails: JobRun failed. Job execution role does not have the
        #                 logs:DescribeLogGroups permission.
        #   failureReason: USER_ERROR
        #
        # which is EMR's own pre-flight check: its submitter calls DescribeLogGroups to find out
        # whether the log group in cloudWatchMonitoringConfiguration already exists. The job
        # therefore never runs, writes no CloudWatch stream, and leaves only a job-metadata.log
        # in S3 - so the failure looks like a Spark or a logging problem rather than an IAM one.
        #
        #   aws iam simulate-custom-policy \
        #     --policy-input-list '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["logs:DescribeLogGroups"],"Resource":["arn:aws:logs:*:*:*"]}]}' \
        #     --action-names logs:DescribeLogGroups
        #   # implicitDeny - and "allowed" only once Resource is "*"
        #
        # This is the one place in this role where rules.md A-5 cannot be satisfied by naming the
        # resource. What keeps it from being a blanket logs grant is the action list: read-only,
        # and the write actions above are still scoped to this group.
        Resource = "*"
      },
    ]
  })
}
