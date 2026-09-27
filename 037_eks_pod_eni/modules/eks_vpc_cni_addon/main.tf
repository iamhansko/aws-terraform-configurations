# vpc-cni is a networking DaemonSet: worker nodes need it running before
# they can join the cluster in a Ready state, so bootstrap_self_managed_
# addons must be false on the cluster (see modules/eks_cluster) and this
# module must be created before the node group. As a DaemonSet, it becomes
# ACTIVE with zero nodes (desired == ready == 0), so it only needs the
# cluster to exist (rules.md C-4). Split into its own module (rather than
# sharing one with kube-proxy) so each EKS-managed addon can be
# independently versioned/upgraded/replaced without affecting the others.
#
# Replaces the previous "kubectl set env daemonset aws-node -n kube-system
# ENABLE_POD_ENI=true / POD_SECURITY_GROUP_ENFORCING_MODE=standard" shell
# commands: the configuration_values map directly to the aws-node
# DaemonSet's environment variables (rules.md E-5).
resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = var.cluster_name
  addon_name                  = "vpc-cni"
  resolve_conflicts_on_create = var.resolve_conflicts_on_create
  resolve_conflicts_on_update = var.resolve_conflicts_on_update

  configuration_values = jsonencode({
    env = {
      ENABLE_POD_ENI                    = tostring(var.enable_pod_eni)
      POD_SECURITY_GROUP_ENFORCING_MODE = var.pod_security_group_enforcing_mode
    }
  })
}
