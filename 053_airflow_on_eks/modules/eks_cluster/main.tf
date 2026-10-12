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
# The control plane's log group, created here rather than left to EKS.
#
# EKS creates /aws/eks/<name>/cluster on its own the first time a log type is enabled, but with no
# retention and outside Terraform state - so it never expires and terraform destroy leaves it behind.
# The blueprint's terraform-aws-modules/eks call created it as a resource with a 90-day retention,
# and this is the same thing. It has to exist before the cluster, or EKS creates its own first and
# this one fails with ResourceAlreadyExistsException - hence the depends_on below.
resource "aws_cloudwatch_log_group" "eks_cluster" {
  count = length(var.enabled_cluster_log_types) > 0 ? 1 : 0

  name              = "/aws/eks/${var.name}/cluster"
  retention_in_days = var.log_retention_days
}
resource "aws_eks_cluster" "eks_cluster" {
  name    = var.name
  version = var.kubernetes_version
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
  # No encryption_config. The blueprint's EKS module created a customer managed KMS key for Secrets
  # by default, but EKS now envelope encrypts all Kubernetes API data with an AWS owned key on every
  # cluster from 1.28 up, so a key of our own would only add a monthly charge and a 30-day pending
  # deletion on every destroy.
  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_iam_role,
    aws_cloudwatch_log_group.eks_cluster,
  ]
}
resource "aws_iam_openid_connect_provider" "eks_oidc_provider" {
  url            = aws_eks_cluster.eks_cluster.identity[0].oidc[0].issuer
  client_id_list = ["sts.amazonaws.com"]
}
