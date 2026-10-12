# metrics-server as an EKS community addon. The blueprint installed it as a Helm chart through
# eks-blueprints-addons (enable_metrics_server); the addon runs the same upstream component and lets
# EKS pick the version that matches the cluster, so it is the same thing with one less chart to pin.
# kubectl top and any HorizontalPodAutoscaler have no resource metrics without it.
#
# Own module per addon, as with vpc-cni/kube-proxy/coredns (rules.md C-4):
# metrics-server is a Deployment, so unlike the DaemonSet addons it needs
# schedulable node capacity to leave DEGRADED, which means the root has to
# order it after the node groups.
resource "aws_eks_addon" "metrics_server" {
  cluster_name                = var.cluster_name
  addon_name                  = "metrics-server"
  addon_version               = var.addon_version
  resolve_conflicts_on_create = var.resolve_conflicts_on_create
  resolve_conflicts_on_update = var.resolve_conflicts_on_update
  configuration_values = jsonencode({
    replicas = var.replica_count
  })
}
