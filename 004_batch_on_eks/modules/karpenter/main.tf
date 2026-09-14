resource "aws_iam_role" "karpenter_controller_iam_role" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = var.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${var.oidc_issuer_host}:sub" = "system:serviceaccount:${var.namespace}:${var.service_account_name}"
          "${var.oidc_issuer_host}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "karpenter_controller_iam_role" {
  for_each   = toset(var.controller_policy_arns)
  role       = aws_iam_role.karpenter_controller_iam_role.name
  policy_arn = each.value
}

resource "aws_iam_role" "karpenter_node_iam_role" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = ["ec2.amazonaws.com"]
      }
      Action = ["sts:AssumeRole"]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "karpenter_node_iam_role" {
  for_each   = toset(var.node_iam_policy_arns)
  role       = aws_iam_role.karpenter_node_iam_role.name
  policy_arn = each.value
}

resource "aws_eks_access_entry" "karpenter_node_iam_access_entry" {
  cluster_name  = var.cluster_name
  principal_arn = aws_iam_role.karpenter_node_iam_role.arn
  type          = "EC2_LINUX"
}

resource "helm_release" "karpenter" {
  name             = "karpenter"
  repository       = "oci://public.ecr.aws/karpenter"
  chart            = "karpenter"
  version          = var.chart_version
  namespace        = var.namespace
  create_namespace = true
  wait             = true

  set = [
    {
      name  = "settings.clusterName"
      value = var.cluster_name
    },
    {
      name  = "controller.resources.requests.cpu"
      value = var.controller_cpu_request
    },
    {
      name  = "controller.resources.requests.memory"
      value = var.controller_memory_request
    },
    {
      name  = "controller.resources.limits.cpu"
      value = var.controller_cpu_limit
    },
    {
      name  = "controller.resources.limits.memory"
      value = var.controller_memory_limit
    },
    {
      name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
      value = aws_iam_role.karpenter_controller_iam_role.arn
    },
  ]

  depends_on = [
    aws_iam_role_policy_attachment.karpenter_controller_iam_role,
    aws_eks_access_entry.karpenter_node_iam_access_entry,
  ]
}
