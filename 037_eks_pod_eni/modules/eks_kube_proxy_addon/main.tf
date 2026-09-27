# kube-proxy is a networking DaemonSet: worker nodes need it running before
# they can join the cluster in a Ready state, so bootstrap_self_managed_
# addons must be false on the cluster (see modules/eks_cluster) and this
# module must be created before the node group. As a DaemonSet, it becomes
# ACTIVE with zero nodes (desired == ready == 0), so it only needs the
# cluster to exist (rules.md C-4). Split into its own module (rather than
# sharing one with vpc-cni) so each EKS-managed addon can be independently
# versioned/upgraded/replaced without affecting the others.
resource "aws_eks_addon" "kube_proxy" {
  cluster_name                = var.cluster_name
  addon_name                  = "kube-proxy"
  resolve_conflicts_on_create = var.resolve_conflicts_on_create
  resolve_conflicts_on_update = var.resolve_conflicts_on_update
}
