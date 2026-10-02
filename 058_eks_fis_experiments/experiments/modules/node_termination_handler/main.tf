# The AWS Node Termination Handler, in its IMDS mode: a DaemonSet that watches each node's own
# instance metadata for a termination notice and drains that node when one appears.
#
# Worth being clear about what this covers, because it overlaps with Karpenter's interruption
# queue and the _monolithic template installed both without saying why.
#
#   Karpenter's queue  covers the nodes Karpenter provisioned. It learns from EventBridge, and
#                      it does more than drain: it launches a replacement before the old node
#                      is gone, because it knows how that node was built.
#   This handler       covers every node, including the managed node group's - which Karpenter
#                      does not manage and would not replace. It learns from IMDS on the node
#                      itself, so it needs no queue and no IAM.
#
# On a Karpenter node both react to the same notice. That is duplicated draining rather than a
# conflict - a cordon and an eviction are both idempotent - but it is the reason this project
# has two mechanisms rather than one, and 060_eks_node_termination_handler is where the handler
# is the subject rather than a supporting part.
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
