# Argo Rollouts, installed with helm_release rather than by the
# 00_install_argorollouts.sh script the _monolithic template cloned from a GitHub
# repository, sed-substituted a region into, and ran over SSM (rules.md E-1). The
# chart version is pinned so the demo does not change shape when upstream releases.
#
# helm rather than kubectl_manifest: the helm provider needs no API server access at
# plan time, only at apply time, so it works even though its configuration depends
# on a cluster created in the same apply (rules.md E-2).
resource "helm_release" "argo_rollouts" {
  name             = var.release_name
  repository       = var.chart_repository
  chart            = var.chart_name
  version          = var.chart_version
  namespace        = var.namespace
  create_namespace = true
  # Holds the apply until the controller Deployment reports Available, so anything
  # ordered after this module can assume a controller exists to reconcile its
  # Rollout objects.
  wait    = true
  timeout = var.timeout_seconds

  set = concat([
    {
      # The dashboard is what makes a blue/green promotion watchable in a browser
      # instead of only through "kubectl argo rollouts get rollout --watch".
      name  = "dashboard.enabled"
      value = tostring(var.dashboard_enabled)
    },
    {
      name  = "controller.replicas"
      value = tostring(var.controller_replica_count)
    },
    ],
    var.additional_set_values,
  )
}
