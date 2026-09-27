# coredns runs as a Deployment (regular pods, not a DaemonSet), so unlike
# vpc-cni/kube-proxy (modules/eks_vpc_cni_addon, modules/eks_kube_proxy_addon)
# it needs schedulable node capacity to leave the DEGRADED state and become
# ACTIVE. Split into its own module so the root can order it after the node
# group exists, while vpc-cni/kube-proxy stay ordered before it (rules.md C-4).
resource "aws_eks_addon" "coredns" {
  cluster_name                = var.cluster_name
  addon_name                  = "coredns"
  addon_version               = var.addon_version
  resolve_conflicts_on_create = var.resolve_conflicts_on_create
  resolve_conflicts_on_update = var.resolve_conflicts_on_update

  # Null when no replica count is given, so the addon keeps its own default and
  # nothing here has an opinion about the number of CoreDNS pods. That is what this
  # variant needs: the cluster-proportional-autoscaler is the one thing that decides
  # it, and a replicaCount pinned in the addon's configuration would be reasserted
  # by EKS on every addon update (rules.md B-4).
  configuration_values = var.coredns_replica_count == null ? null : jsonencode({
    replicaCount = var.coredns_replica_count
  })
}
