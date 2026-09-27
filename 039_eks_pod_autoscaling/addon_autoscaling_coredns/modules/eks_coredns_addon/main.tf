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

  # autoScaling and replicaCount are alternatives, not companions: with autoscaling
  # on, the addon installs its own horizontal autoscaler for the coredns Deployment
  # and a fixed replicaCount would be immediately overwritten by it. So only one of
  # the two is ever sent.
  #
  # This is the whole point of this variant, and it replaces what the other CoreDNS
  # scaling approach needs a separate Helm release for: the addon does it natively
  # (rules.md E-5).
  # jsonencode is inside each branch rather than wrapped around the conditional.
  # Terraform requires a conditional's two results to share a type, and two objects
  # with different attributes do not - it rejects them with "Inconsistent conditional
  # result types". Encoding first makes both branches plain strings.
  configuration_values = var.autoscaling_enabled ? jsonencode({
    autoScaling = {
      enabled     = true
      minReplicas = var.autoscaling_min_replicas
      maxReplicas = var.autoscaling_max_replicas
    }
    }) : jsonencode({
    replicaCount = var.coredns_replica_count
  })
}
