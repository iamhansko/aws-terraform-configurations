resource "helm_release" "rancher" {
  name             = var.release_name
  repository       = var.chart_repository
  chart            = "rancher"
  version          = var.chart_version
  namespace        = var.namespace
  create_namespace = true
  wait             = true
  timeout          = var.timeout_seconds

  set = concat([
    # Rancher builds its Ingress and its own redirects from this, and rejects
    # requests whose Host header does not match, so it has to be the address users
    # actually reach rather than a placeholder.
    {
      name  = "hostname"
      value = var.hostname
    },
    {
      name  = "ingress.ingressClassName"
      value = var.ingress_class_name
    },
    {
      name  = "replicas"
      value = tostring(var.replicas)
    },
    {
      name  = "bootstrapPassword"
      value = var.bootstrap_password
      # The password has to arrive as a string. A value that happens to be all
      # digits would otherwise be inferred as a number and rejected by the chart's
      # template, which is the kind of failure that only shows up for some
      # passwords (rules.md E-7).
      type = "string"
    },
    ],
    var.additional_set_values,
  )
}
