# Kyverno and its policy bundle are one module rather than two: the policies chart
# is meaningless without the admission controller that evaluates them, and it is
# published from the same repository at a matching version (rules.md C-2).
resource "helm_release" "kyverno" {
  name             = var.release_name
  repository       = var.chart_repository
  chart            = "kyverno"
  version          = var.chart_version
  namespace        = var.namespace
  create_namespace = var.create_namespace
  # Kyverno puts admission webhooks in front of pod creation cluster-wide. Waiting
  # matters more here than for most charts: a webhook registered before its backing
  # pod is ready makes every pod creation in the cluster fail until it comes up.
  wait    = true
  timeout = var.timeout_seconds

  set = concat([
    {
      name  = "grafana.enabled"
      value = tostring(var.enable_grafana_dashboard)
    },
    {
      name  = "grafana.grafanaDashboard.create"
      value = tostring(var.enable_grafana_dashboard)
    },
    ],
    var.additional_set_values,
  )
}
resource "helm_release" "kyverno_policies" {
  name       = var.policies_release_name
  repository = var.chart_repository
  chart      = "kyverno-policies"
  version    = var.policies_chart_version
  namespace  = var.namespace
  # The namespace already exists by now, whoever created it.
  create_namespace = false
  wait             = true
  timeout          = var.timeout_seconds

  set = [
    {
      name  = "podSecurityStandard"
      value = var.pod_security_standard
    },
    {
      # Case-sensitive from Kyverno 1.11: "audit" in lowercase is rejected rather
      # than normalised.
      name  = "validationFailureAction"
      value = var.validation_failure_action
      type  = "string"
    },
  ]

  # The policies are ClusterPolicy custom resources, so Kyverno's CRDs have to be
  # registered before this chart's objects can be created. The release above
  # installs them, and nothing in these values expresses that (rules.md D-1).
  depends_on = [helm_release.kyverno]
}
