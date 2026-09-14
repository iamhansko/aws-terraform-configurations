# vpc-cni is a networking DaemonSet; a DaemonSet with no nodes yet is
# trivially "complete" (desired == ready == 0), so unlike coredns
# (modules/eks_coredns_addon) it doesn't need compute capacity to become
# ACTIVE. It only needs the cluster to exist, which the cluster_name
# reference below already orders this module after (rules.md #28). Split
# into its own module (rather than sharing one with kube-proxy) so each
# EKS-managed addon can be independently versioned/upgraded/replaced
# without affecting the others.
#
# Replaces the previous "kubectl set env daemonset aws-node -n kube-system
# ENABLE_POD_ENI=true" shell command: the configuration_values map directly
# to the aws-node DaemonSet's environment variables (rules.md #23).
resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = var.cluster_name
  addon_name                  = "vpc-cni"
  resolve_conflicts_on_create = var.resolve_conflicts_on_create
  resolve_conflicts_on_update = var.resolve_conflicts_on_update

  configuration_values = jsonencode({
    env = {
      ENABLE_POD_ENI = tostring(var.enable_pod_eni)
    }
  })
}
