# coredns runs as a Deployment (regular pods), so unlike vpc-cni/kube-proxy
# (modules/eks_vpc_cni_addon, modules/eks_kube_proxy_addon, DaemonSets that
# are trivially "complete" with zero nodes) it needs schedulable capacity
# to leave the DEGRADED state and become ACTIVE. Split into its own module
# so the root can order it after node capacity
# (eks_fargate_profile/eks_node_group/karpenter) exists, while vpc-cni/
# kube-proxy stay ordered before it (rules.md #28).
resource "aws_eks_addon" "coredns" {
  cluster_name                = var.cluster_name
  addon_name                  = "coredns"
  resolve_conflicts_on_create = var.resolve_conflicts_on_create
  resolve_conflicts_on_update = var.resolve_conflicts_on_update

  configuration_values = jsonencode({
    replicaCount = var.coredns_replica_count
  })
}
