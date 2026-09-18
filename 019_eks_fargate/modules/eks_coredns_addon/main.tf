# coredns runs as a Deployment (regular pods, not a DaemonSet), so unlike
# vpc-cni/kube-proxy (modules/eks_vpc_cni_addon, modules/eks_kube_proxy_addon)
# it needs schedulable capacity to leave the DEGRADED state and become ACTIVE.
# Split into its own module so the root can order it after that capacity exists
# (rules.md C-4). In this project the capacity is a Fargate profile selecting
# kube-system, not a node group.
#
# compute_type is what makes CoreDNS work on a cluster with no EC2 nodes at all.
# EKS ships the Deployment with an eks.amazonaws.com/compute-type: ec2
# annotation, and with that annotation the pods stay Pending forever on a
# Fargate-only cluster - the cluster comes up with no working DNS. Setting it to
# Fargate here removes that annotation declaratively, which is why this project
# needs no rollout-restart step at all (contrast rules.md E-4, which triggers a
# rollout for a Deployment whose placement cannot be expressed as addon
# configuration).
resource "aws_eks_addon" "coredns" {
  cluster_name                = var.cluster_name
  addon_name                  = "coredns"
  addon_version               = var.addon_version
  resolve_conflicts_on_create = var.resolve_conflicts_on_create
  resolve_conflicts_on_update = var.resolve_conflicts_on_update

  configuration_values = jsonencode({
    replicaCount = var.coredns_replica_count
    computeType  = var.compute_type
  })
}
