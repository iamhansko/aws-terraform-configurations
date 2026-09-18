# EKS Auto Mode. The difference from an ordinary cluster is not a feature flag on
# the side: AWS takes over compute, load balancing and block storage, so the
# cluster role needs four more managed policies than a normal one, a node role has
# to exist before the cluster is created, and the three add-ons every other EKS
# project in this repository declares (vpc-cni, kube-proxy, coredns) must not be
# installed at all - Auto Mode provides those capabilities itself.
resource "aws_iam_role" "eks_auto_cluster_role" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = ["eks.amazonaws.com"]
      }
      # sts:TagSession alongside sts:AssumeRole, which a non-Auto-Mode cluster role
      # does not need. Auto Mode tags the sessions it assumes for its managed
      # capabilities, and the cluster create call is rejected if the trust policy
      # does not allow it.
      Action = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
}
resource "aws_iam_role_policy_attachment" "eks_auto_cluster_role" {
  for_each   = toset(var.cluster_iam_policy_arns)
  role       = aws_iam_role.eks_auto_cluster_role.name
  policy_arn = each.value
}
# The role the nodes Auto Mode launches will carry. It has to exist before the
# cluster, because compute_config names it - unlike a managed node group, where the
# node role is created alongside the group after the cluster.
resource "aws_iam_role" "eks_auto_node_role" {
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
resource "aws_iam_role_policy_attachment" "eks_auto_node_role" {
  for_each   = toset(var.node_iam_policy_arns)
  role       = aws_iam_role.eks_auto_node_role.name
  policy_arn = each.value
}
resource "aws_eks_cluster" "eks_cluster" {
  name    = var.name
  version = var.kubernetes_version
  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }
  # False because Auto Mode manages the CNI, kube-proxy and CoreDNS capabilities
  # itself. Leaving it true would have EKS install self-managed copies of the three
  # alongside Auto Mode's own, which is why this project has no addon modules at all
  # - the one place in this repository where rules.md C-4 does not apply.
  # Changing this value forces cluster replacement.
  bootstrap_self_managed_addons = false
  vpc_config {
    endpoint_private_access = var.endpoint_private_access
    endpoint_public_access  = var.endpoint_public_access
    public_access_cidrs     = var.endpoint_public_access ? var.public_access_cidrs : null
    security_group_ids      = var.additional_security_group_ids
    subnet_ids              = var.subnet_ids
  }
  role_arn = aws_iam_role.eks_auto_cluster_role.arn

  # The three blocks that make this Auto Mode. All of them have to be on together:
  # EKS rejects a cluster with compute_config enabled while block storage or
  # load balancing is off.
  compute_config {
    enabled = var.compute_enabled
    # general-purpose carries the workload, system carries the cluster's own
    # components. Dropping system leaves nothing to run CoreDNS on and the cluster
    # comes up without working DNS.
    node_pools    = var.node_pools
    node_role_arn = aws_iam_role.eks_auto_node_role.arn
  }
  kubernetes_network_config {
    elastic_load_balancing {
      # Auto Mode's built-in load balancing controller. This is what replaces the
      # AWS Load Balancer Controller Helm release the other projects install
      # themselves.
      enabled = var.elastic_load_balancing_enabled
    }
    ip_family         = var.ip_family
    service_ipv4_cidr = var.service_ipv4_cidr
  }
  storage_config {
    block_storage {
      # Auto Mode's built-in EBS CSI driver.
      enabled = var.block_storage_enabled
    }
  }

  enabled_cluster_log_types = var.enabled_cluster_log_types

  # EKS validates both roles' policies when the cluster is created, and referencing
  # the role ARNs alone does not order this after the attachments (rules.md D-1).
  depends_on = [
    aws_iam_role_policy_attachment.eks_auto_cluster_role,
    aws_iam_role_policy_attachment.eks_auto_node_role,
  ]
}
resource "aws_iam_openid_connect_provider" "eks_oidc_provider" {
  url            = aws_eks_cluster.eks_cluster.identity[0].oidc[0].issuer
  client_id_list = ["sts.amazonaws.com"]
}
