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
  name    = var.name
  version = var.kubernetes_version
  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }
  # Prevents EKS from installing vpc-cni/coredns/kube-proxy as unmanaged self-managed addons at cluster
  # creation, so they are exclusively managed by the aws_eks_addon resources in modules/eks_vpc_cni_addon,
  # modules/eks_kube_proxy_addon and modules/eks_coredns_addon instead. The _monolithic template already set
  # BootstrapSelfManagedAddons: false, so this is what it had (rules.md C-4).
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
  # Both halves of the _monolithic template's KubernetesNetworkConfig. service_ipv4_cidr is worth declaring
  # rather than leaving to EKS: it is immutable after creation, and the value EKS picks by default depends on
  # whether the VPC's own CIDR overlaps 172.20.0.0/16 - so leaving it out makes the cluster's service range a
  # function of the network rather than a decision.
  kubernetes_network_config {
    ip_family         = var.ip_family
    service_ipv4_cidr = var.ip_family == "ipv4" ? var.service_ipv4_cidr : null
  }

  depends_on = [aws_iam_role_policy_attachment.eks_cluster_iam_role]
}
# Registered even though nothing in this project uses the cluster's OIDC provider for a workload: the AWS Load
# Balancer Controller's role trusts it (modules/aws_load_balancer_controller_iam_role), and without the
# provider registered in IAM that trust policy is accepted and then fails at AssumeRoleWithWebIdentity - which
# appears as AccessDenied in the controller's log rather than anywhere in IAM.
resource "aws_iam_openid_connect_provider" "eks_oidc_provider" {
  url            = aws_eks_cluster.eks_cluster.identity[0].oidc[0].issuer
  client_id_list = ["sts.amazonaws.com"]
}
