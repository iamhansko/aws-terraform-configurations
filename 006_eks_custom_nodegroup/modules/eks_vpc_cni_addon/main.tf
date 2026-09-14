# vpc-cni is a networking DaemonSet: worker nodes need it running before they
# can join the cluster in a Ready state, so bootstrap_self_managed_addons must
# be false on the cluster (see modules/eks_cluster) and this module must be
# created before any node capacity. As a DaemonSet it becomes ACTIVE with zero
# nodes (desired == ready == 0), so it only needs the cluster to exist
# (rules.md #28). Split into its own module - rather than sharing one with
# kube-proxy/coredns - so each EKS-managed addon can be independently
# versioned, upgraded and ordered.
resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = var.cluster_name
  addon_name                  = "vpc-cni"
  addon_version               = var.addon_version
  resolve_conflicts_on_create = var.resolve_conflicts_on_create
  resolve_conflicts_on_update = var.resolve_conflicts_on_update

  # Maps to the aws-node DaemonSet's environment variables, replacing any
  # "kubectl set env daemonset aws-node -n kube-system ..." shell step
  # (rules.md #23).
  configuration_values = length(var.env) > 0 ? jsonencode({ env = var.env }) : null
}
