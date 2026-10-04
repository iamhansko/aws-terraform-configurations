# vpc-cni is a networking DaemonSet: worker nodes need it running before they can join the cluster in a Ready
# state, so bootstrap_self_managed_addons must be false on the cluster (see modules/eks_cluster) and this
# module must be created before any node capacity. As a DaemonSet it becomes ACTIVE with zero nodes
# (desired == ready == 0), so it only needs the cluster to exist (rules.md C-4). Split into its own module -
# rather than sharing one with kube-proxy/coredns - so each EKS-managed addon can be independently versioned,
# upgraded and ordered.
#
# It also matters to the Gateway API demo in this project: the Gateway's target groups use target type ip, and
# that only works because the VPC CNI gives pods addresses the VPC can route to directly (rules.md G-1).
resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = var.cluster_name
  addon_name                  = "vpc-cni"
  addon_version               = var.addon_version
  resolve_conflicts_on_create = var.resolve_conflicts_on_create
  resolve_conflicts_on_update = var.resolve_conflicts_on_update
  # The aws-node DaemonSet's environment variables, set declaratively instead of through a
  # "kubectl set env daemonset aws-node -n kube-system ..." shell step (rules.md E-5). Empty by default, as
  # the _monolithic template had it: it declared the addon with nothing but ResolveConflicts.
  #
  # Dropped entirely rather than sent as an empty object when unset, so an unconfigured addon gets no
  # configuration_values at all and EKS applies its own defaults.
  configuration_values = length(var.env) > 0 ? jsonencode({ env = var.env }) : null
}
