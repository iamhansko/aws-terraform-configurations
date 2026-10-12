# The blueprint's EMR on EKS virtual cluster (emr-eks.tf), which it built with
# terraform-aws-modules/emr's virtual-cluster submodule: the virtual cluster, the role its jobs run
# as, and the log group a job writes to. The namespace and the RBAC that module also created are in
# modules/emr_namespace_access, because they are Kubernetes objects and this module makes only AWS
# API calls.
#
# One module because they are one component: the virtual cluster is useless without a job execution
# role, the role's trust policy names the virtual cluster's namespace, and the log group exists only
# to be named in a job's monitoringConfiguration - the same reasoning that keeps a controller's IAM
# role next to its Helm release (rules.md C-2).
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
# The role a Spark job assumes, through IRSA.
#
# EMR on EKS creates its own service accounts per job, named
# emr-containers-sa-<component>-<id>-<account>-<base36 role name>, and does not create Pod Identity
# associations for them. The trust policy therefore has to match a name it cannot know in advance,
# which is what the StringLike wildcard is for - the same condition the upstream module wrote, and
# what `aws emr-containers update-role-trust-policy` writes when done by hand.
resource "aws_iam_role" "job_execution" {
  name_prefix = "${substr(var.name, 0, 33)}-"
  description = "Job execution role for EMR on EKS ${var.name} virtual cluster"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Carried over from the upstream module unchanged. The pods of a job assume the role through
        # the IRSA statement below, not through this one.
        Sid       = "EMR"
        Effect    = "Allow"
        Principal = { Service = "elasticmapreduce.amazonaws.com" }
        Action    = "sts:AssumeRole"
      },
      {
        Sid       = "IRSA"
        Effect    = "Allow"
        Principal = { Federated = var.oidc_provider_arn }
        Action    = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          # StringLike, not StringEquals: the service account name carries a base36 encoding of this
          # role's own generated name, so the exact value is not knowable here. Scoped to the one
          # namespace and this account, which is what keeps the wildcard from meaning "any service
          # account in the cluster".
          StringLike = {
            "${var.oidc_issuer_host}:sub" = "system:serviceaccount:${var.namespace}:emr-containers-sa-*-*-${var.account_id}-*"
          }
          StringEquals = {
            "${var.oidc_issuer_host}:aud" = "sts.amazonaws.com"
          }
        }
      },
    ]
  })
}
resource "aws_cloudwatch_log_group" "job" {
  name              = var.log_group_name
  retention_in_days = var.log_retention_days
}
# The log group only. The upstream module's policy also granted s3:GetObject/PutObject/DeleteObject
# and s3:ListBucket on "*", but the blueprint attached AmazonS3FullAccess on top through
# iam_role_additional_policies, which already covers all of it - so S3 access is decided in one place,
# additional_policy_arns, and the example DAG's job (pi.py, shipped inside the EMR image) needs none.
resource "aws_iam_role_policy" "job_execution" {
  name = "job-execution"
  role = aws_iam_role.job_execution.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = ["logs:PutLogEvents", "logs:CreateLogStream", "logs:DescribeLogStreams"]
        # The log group and its streams. These three support resource-level permissions, so they
        # stay scoped to this one group - unlike DescribeLogGroups below.
        Resource = ["${aws_cloudwatch_log_group.job.arn}:*"]
      },
      {
        Sid    = "CloudWatchLogsReadOnly"
        Effect = "Allow"
        Action = ["logs:DescribeLogGroups"]
        # "*", and it cannot be narrowed. DescribeLogGroups is a list operation over the account and
        # CloudWatch Logs does not support resource-level permissions for it, so a grant naming a log
        # group ARN authorises nothing. EMR's submitter calls it before any pod exists, to find out
        # whether the log group in cloudWatchMonitoringConfiguration is there - and without it the job
        # fails with "Job execution role does not have the logs:DescribeLogGroups permission", having
        # written no log stream that would say so.
        Resource = "*"
      },
    ]
  })
}
# for_each over literal ARNs, which are known at plan time (rules.md B-7).
resource "aws_iam_role_policy_attachment" "job_execution_additional" {
  for_each   = toset(var.additional_policy_arns)
  role       = aws_iam_role.job_execution.name
  policy_arn = each.value
}
