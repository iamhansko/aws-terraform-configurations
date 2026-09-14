# kube-proxy is a networking DaemonSet; a DaemonSet with no nodes yet is
# trivially "complete" (desired == ready == 0), so unlike coredns
# (modules/eks_coredns_addon) it doesn't need compute capacity to become
# ACTIVE. It only needs the cluster to exist, which the cluster_name
# reference below already orders this module after (rules.md #28). Split
# into its own module (rather than sharing one with vpc-cni) so each
# EKS-managed addon can be independently versioned/upgraded/replaced
# without affecting the others.
resource "aws_eks_addon" "kube_proxy" {
  cluster_name                = var.cluster_name
  addon_name                  = "kube-proxy"
  resolve_conflicts_on_create = var.resolve_conflicts_on_create
  resolve_conflicts_on_update = var.resolve_conflicts_on_update
}
