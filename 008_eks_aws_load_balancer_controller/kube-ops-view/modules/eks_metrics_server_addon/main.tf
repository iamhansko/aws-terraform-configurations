# metrics-server is an EKS community addon, so it replaces the
# "kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/
# latest/download/components.yaml" step the _monolithic bastion ran, and EKS
# tracks its version instead of the cluster silently pinning whatever "latest"
# resolved to on bootstrap day (rules.md E-1).
#
# The Horizontal Pod Autoscaler has no resource metrics without it, so the HPA
# demo in modules/hpa_demo depends on this addon being ACTIVE.
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
