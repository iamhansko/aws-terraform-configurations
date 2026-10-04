# coredns runs as a Deployment (regular pods, not a DaemonSet), so unlike vpc-cni/kube-proxy
# (modules/eks_vpc_cni_addon, modules/eks_kube_proxy_addon) it needs schedulable node capacity to leave the
# DEGRADED state and become ACTIVE. Split into its own module so the root can order it after the node group,
# while vpc-cni/kube-proxy stay ordered before it (rules.md C-4).
#
# The _monolithic template declared all three addons together with no ordering at all. On a cluster with
# BootstrapSelfManagedAddons: false - which it also set - that means coredns was created at the same time as
# the node group and would sit DEGRADED until nodes happened to come up, failing the create with
# "timeout while waiting for state to become 'ACTIVE'" if they did not.
resource "aws_eks_addon" "coredns" {
  cluster_name                = var.cluster_name
  addon_name                  = "coredns"
  addon_version               = var.addon_version
  resolve_conflicts_on_create = var.resolve_conflicts_on_create
  resolve_conflicts_on_update = var.resolve_conflicts_on_update
  configuration_values = jsonencode({
    replicaCount = var.coredns_replica_count
  })
}
