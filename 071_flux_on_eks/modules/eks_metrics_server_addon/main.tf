# metrics-server, the source of the numbers a HorizontalPodAutoscaler scales on.
#
# Why it is needed here at all. podinfo's kustomize directory includes a HorizontalPodAutoscaler,
# and it arrives whether or not anything can measure CPU. Without a metrics API that HPA reports
# "cpu: <unknown>" in its TARGETS column and carries a ScalingActive=False condition with
# FailedGetResourceMetric.
#
# What it still does in that state is worth being precise about, because it is easy to over-claim:
# the replica floor is enforced regardless, so the GOAL.md step that commits minReplicas: 4 does
# scale the Deployment to four with no metrics anywhere. What does not work is the autoscaling -
# the controller cannot compute a desired count from CPU, so nothing moves with load, in either
# direction. Nothing reports a problem either: an HPA counts as Ready without its metrics, so the
# Kustomization that applied it goes green.
#
# An EKS addon rather than the upstream Helm chart, which is the other way this is usually
# installed. It is a community addon rather than an AWS one - owner "community", type
# "observability" - but it is in the addon catalogue, so it is created by the AWS provider through
# the EKS API and is in state with a version this configuration pins, rather than being a
# helm_release that has to wait for the API server to be reachable.
#
# Its own module, as every addon in this project has (rules.md C-4): the ordering requirement here
# is coredns's rather than vpc-cni's, and bundling addons together would force them all to wait
# for the strictest one.
resource "aws_eks_addon" "metrics_server" {
  cluster_name                = var.cluster_name
  addon_name                  = "metrics-server"
  addon_version               = var.addon_version
  resolve_conflicts_on_create = var.resolve_conflicts_on_create
  resolve_conflicts_on_update = var.resolve_conflicts_on_update

  # The addon's own default is two, and its pod anti-affinity is preferred rather than required -
  # so on a single-node cluster both replicas schedule onto the one node instead of leaving one
  # Pending and the addon DEGRADED, which is how that failure would otherwise look
  # (rules.md C-4/E-5).
  configuration_values = jsonencode({
    replicas = var.replicas
  })
}
