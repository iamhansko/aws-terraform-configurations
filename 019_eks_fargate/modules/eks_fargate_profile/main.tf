data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

# The pod execution role belongs to this module rather than to the root: a
# Fargate profile cannot exist without one, and nothing outside the module has a
# use for it. Each profile gets its own role, as the _monolithic template had it,
# so the ArnLike condition below can be narrowed per profile if the demo ever
# needs it.
resource "aws_iam_role" "fargate_pod_execution_iam_role" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = ["eks-fargate-pods.amazonaws.com"]
      }
      Action = ["sts:AssumeRole"]
      # Confused-deputy guard: only this cluster's Fargate profiles may assume
      # the role, not any Fargate profile in the account.
      Condition = {
        ArnLike = {
          "aws:SourceArn" = "arn:aws:eks:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:fargateprofile/${var.cluster_name}/*"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "fargate_pod_execution_iam_role" {
  role       = aws_iam_role.fargate_pod_execution_iam_role.name
  policy_arn = var.pod_execution_policy_arn
}

resource "aws_eks_fargate_profile" "fargate_profile" {
  cluster_name           = var.cluster_name
  fargate_profile_name   = var.profile_name
  pod_execution_role_arn = aws_iam_role.fargate_pod_execution_iam_role.arn
  subnet_ids             = var.subnet_ids
  selector {
    namespace = var.namespace
  }

  # EKS rejects the create call unless the pod execution role already carries
  # AmazonEKSFargatePodExecutionRolePolicy, and referencing the role's ARN alone
  # does not order this after the attachment (rules.md D-1).
  depends_on = [aws_iam_role_policy_attachment.fargate_pod_execution_iam_role]
}
