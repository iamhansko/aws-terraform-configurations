data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

resource "aws_iam_role" "fargate_pod_execution_iam_role" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = ["eks-fargate-pods.amazonaws.com"]
      }
      Action = ["sts:AssumeRole"]
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
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSFargatePodExecutionRolePolicy"
}

resource "aws_eks_fargate_profile" "fargate_profile" {
  cluster_name           = var.cluster_name
  fargate_profile_name   = var.profile_name
  pod_execution_role_arn = aws_iam_role.fargate_pod_execution_iam_role.arn
  subnet_ids             = var.subnet_ids
  selector {
    namespace = var.namespace
  }

  depends_on = [aws_iam_role_policy_attachment.fargate_pod_execution_iam_role]
}

# Declared as a raw manifest via the alekc/kubectl provider (kubectl_manifest)
# instead of hashicorp/kubernetes' kubernetes_annotations, so the whole root
# module (EKS cluster + this rollout trigger) can apply in a single
# `terraform apply` (rules.md E-2). Only spec.template.metadata.annotations
# is set; kubectl_manifest's merge-patch semantics leave every other field of
# the existing coredns Deployment (containers, replicas, etc.) untouched, the
# same way the previous kubernetes_annotations resource's template_annotations
# only ever touched the pod template's annotations map.
resource "kubectl_manifest" "reschedule_deployment" {
  count = var.reschedule_deployment_name != null ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "apps/v1"
    kind       = "Deployment"
    metadata = {
      name      = var.reschedule_deployment_name
      namespace = var.namespace
    }
    spec = {
      template = {
        metadata = {
          annotations = {
            "terraform.io/restartedAt" = timestamp()
          }
        }
      }
    }
  })

  depends_on = [aws_eks_fargate_profile.fargate_profile]

  lifecycle {
    # timestamp() changes on every apply; without this the resource would
    # trigger a fresh rollout every single apply instead of only the first
    # time (same reasoning as the original template_annotations ignore).
    ignore_changes = [yaml_body]
  }
}
