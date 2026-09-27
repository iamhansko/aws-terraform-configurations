# The _monolithic template installed this with "helm upgrade --install" from an SSM
# Association on the bastion, so nothing tracked the release, the chart version
# floated, and a failed install only showed up in the association's output. It is a
# helm_release here (rules.md E-1). hashicorp/helm needs no cluster access at plan
# time, so it works in the same apply that creates the cluster and does not need the
# alekc/kubectl workaround (rules.md E-2).
resource "helm_release" "cluster_proportional_autoscaler" {
  name             = var.release_name
  repository       = var.chart_repository
  chart            = "cluster-proportional-autoscaler"
  version          = var.chart_version
  namespace        = var.namespace
  create_namespace = var.create_namespace
  # Holds the apply until the autoscaler Deployment is Available, which is what the
  # _monolithic script's "helm ... --wait" did.
  wait    = true
  timeout = var.timeout_seconds
  set = concat([
    {
      name  = "options.target"
      value = var.target
    },
    # The namespace the autoscaler looks for its target in, which is separate from
    # the namespace the release is installed into.
    {
      name  = "options.namespace"
      value = var.namespace
    },
    {
      name  = "config.linear.nodesPerReplica"
      value = tostring(var.nodes_per_replica)
    },
    {
      name  = "config.linear.min"
      value = tostring(var.min_replicas)
    },
    {
      name  = "config.linear.max"
      value = tostring(var.max_replicas)
    },
    # These two must reach the chart as booleans, so no type = "string" here - and
    # this is a case where E-7's usual fix would break things rather than fix them.
    # The chart renders config.linear with toJson into a ConfigMap, and the
    # autoscaler unmarshals that JSON into a Go struct whose fields are bools:
    #
    #   auto:   {"includeUnschedulableNodes":true,...,"preventSinglePointFailure":true}
    #   string: {"includeUnschedulableNodes":"true",...,"preventSinglePointFailure":"true"}
    #
    # The second form is valid JSON that fails to unmarshal, so the autoscaler starts
    # and then errors on its own config. The _monolithic template wrote --set
    # ...="true" with the quotes, which happens to be correct only because helm's
    # auto inference turns "true" into a boolean (rules.md E-7).
    {
      name  = "config.linear.preventSinglePointFailure"
      value = tostring(var.prevent_single_point_failure)
    },
    {
      name  = "config.linear.includeUnschedulableNodes"
      value = tostring(var.include_unschedulable_nodes)
    },
    ],
    var.additional_set_values,
  )
}
