# The AWS Node Termination Handler in its IMDS mode: a DaemonSet whose pod on each node polls
# that node's own instance metadata and drains the node when a termination notice appears.
#
# IMDS mode is the subject of this variant, so it is worth stating what it does and does not
# cover. The handler has two modes and they see different things:
#
#   IMDS mode (here)  each pod sees only its own instance, and only the events instance metadata
#                     carries - spot interruption, rebalance recommendation, scheduled
#                     maintenance. It needs no AWS credentials, no queue and no IAM role, which
#                     is the whole appeal: a DaemonSet and nothing else.
#   Queue mode        one Deployment reads AWS events for the entire cluster, which adds the one
#                     event a node cannot learn about itself - an Auto Scaling group lifecycle
#                     hook firing because the group is scaling in or replacing the instance. It
#                     costs an SQS queue, five EventBridge rules, lifecycle hooks and an IRSA
#                     role. nth_queue_processor is that variant.
#
# So a spot interruption is drained in both modes; a scale-in is drained only in queue mode. The
# demo here sends a real interruption with the amazon-ec2-spot-interrupter CLI, which is an event
# IMDS carries.
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
