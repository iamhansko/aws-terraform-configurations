# metrics-server as an EKS community addon, where the blueprint installed the Helm chart (3.12.0, the
# eks-blueprints-addons default) with helm-values/metrics-server-values.yaml. The addon is the shape the
# other EKS projects in this repository use: EKS tracks a version compatible with the cluster's
# Kubernetes version, and the addon is one aws_eks_addon rather than a release plus values file.
#
# Two replicas, as the blueprint's values had them. Those values also spread the replicas with a
# required anti-affinity and gave them a PodDisruptionBudget; this module sets only the replica count,
# which is the one key this repository has checked against the addon's configuration schema
# (rules.md E-5).
#
# Own module per addon, as with vpc-cni/kube-proxy/coredns (rules.md C-4). metrics-server is a
# Deployment, so unlike the DaemonSet addons it needs schedulable node capacity to leave DEGRADED,
# which is why the root orders it after the node group.
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
