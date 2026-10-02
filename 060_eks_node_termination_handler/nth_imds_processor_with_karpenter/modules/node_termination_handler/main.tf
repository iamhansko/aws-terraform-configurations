# The AWS Node Termination Handler in its IMDS mode: a DaemonSet whose pod on each node polls
# that node's own instance metadata and drains the node when a termination notice appears.
#
# This variant runs it alongside Karpenter, which has its own interruption queue, so the two
# overlap. What each actually covers:
#
#   This handler      every node, including the managed node group's - which Karpenter does not
#                     manage and would not replace. It reads IMDS on the node itself, so it
#                     needs no queue, no IAM role and no credentials.
#   Karpenter's queue only the nodes Karpenter provisioned. It learns from EventBridge, and it
#                     does more than drain: it launches a replacement before the old node is
#                     gone, because it knows how that node was built.
#
# On a Karpenter node both react to the same notice. That is duplicated draining rather than a
# conflict - a cordon and an eviction are both idempotent - and it is the reason this variant
# exists next to nth_imds_processor: the interesting question is what the handler adds once
# Karpenter is already handling its own capacity, and the answer is the managed node group.
#
# What neither covers is an Auto Scaling scale-in of the managed node group, since no instance
# can learn that from its own metadata. nth_queue_processor is the variant that does.
resource "helm_release" "node_termination_handler" {
  name = var.release_name
  # An OCI reference is passed as the chart with no repository argument.
  chart     = var.chart
  version   = var.chart_version
  namespace = var.namespace
  # kube-system already exists, but this keeps the module from depending on that.
  create_namespace = true
  # Holds the apply until the DaemonSet is ready, which is what the _monolithic script's
  # "--wait" did.
  wait    = true
  timeout = var.timeout_seconds

  set = concat([
    # All four render as bare booleans. The chart guards none of them with a kindIs check, so a
    # quoted string would be truthy in a Go template and every one of these would read as
    # enabled regardless of the value - which is the failure mode rules.md E-7 describes, with
    # the additional twist that here the wrong answer is always "on".
    {
      name  = "enableSpotInterruptionDraining"
      value = tostring(var.enable_spot_interruption_draining)
    },
    {
      name  = "enableRebalanceMonitoring"
      value = tostring(var.enable_rebalance_monitoring)
    },
    {
      name  = "enableRebalanceDraining"
      value = tostring(var.enable_rebalance_draining)
    },
    {
      name  = "enableScheduledEventDraining"
      value = tostring(var.enable_scheduled_event_draining)
    },
    ],
    var.additional_set_values,
  )
}
