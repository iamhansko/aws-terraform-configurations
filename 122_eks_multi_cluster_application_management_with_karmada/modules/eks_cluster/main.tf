resource "aws_iam_role" "eks_cluster_iam_role" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = ["eks.amazonaws.com"]
      }
      Action = ["sts:AssumeRole"]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster_iam_role" {
  for_each   = toset(var.cluster_iam_policy_arns)
  role       = aws_iam_role.eks_cluster_iam_role.name
  policy_arn = each.value
}

resource "aws_eks_cluster" "eks_cluster" {
  name = var.name
  # null rather than the string "latest". The guidance installer this project replaces accepted "latest" and
  # resolved it by asking the EKS API which cluster versions its addons currently support, taking the last
  # one; aws_eks_cluster has no equivalent, and passing the literal string fails with an InvalidParameter
  # error on the version field. Leaving it unset makes EKS choose its own default version, which is the
  # nearest honest equivalent - and it is not the same thing, because EKS's default trails the newest
  # supported version by a release or two. Pin a version instead of relying on it (rules.md B-1).
  version = var.kubernetes_version == "latest" ? null : var.kubernetes_version
  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }
  # Prevents EKS from installing vpc-cni/coredns/kube-proxy as unmanaged
  # self-managed addons at cluster creation, so they are exclusively managed
  # by the aws_eks_addon resources in modules/eks_vpc_cni_addon,
  # modules/eks_kube_proxy_addon, and modules/eks_coredns_addon instead.
  # Changing this value forces cluster replacement.
  bootstrap_self_managed_addons = false
  vpc_config {
    endpoint_private_access = var.endpoint_private_access
    endpoint_public_access  = var.endpoint_public_access
    public_access_cidrs     = var.endpoint_public_access ? var.public_access_cidrs : null
    security_group_ids      = var.additional_security_group_ids
    subnet_ids              = var.subnet_ids
  }
  role_arn                  = aws_iam_role.eks_cluster_iam_role.arn
  enabled_cluster_log_types = var.enabled_cluster_log_types

  depends_on = [aws_iam_role_policy_attachment.eks_cluster_iam_role]
}

resource "aws_iam_openid_connect_provider" "eks_oidc_provider" {
  url            = aws_eks_cluster.eks_cluster.identity[0].oidc[0].issuer
  client_id_list = ["sts.amazonaws.com"]
}
