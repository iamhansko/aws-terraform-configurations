# Rancher will not install without cert-manager: it issues a self-signed
# certificate for its own ingress and needs the Certificate and Issuer CRDs plus a
# running webhook to do it. That is the whole reason this module exists here, and
# why the caller orders Rancher after it.
resource "helm_release" "cert_manager" {
  name             = var.release_name
  repository       = var.chart_repository
  chart            = "cert-manager"
  version          = var.chart_version
  namespace        = var.namespace
  create_namespace = true
  # Holds the apply until the webhook is actually serving. Without it the next
  # release can start creating Certificate objects while the webhook is still
  # coming up, and those requests fail with a connection error rather than
  # queueing - which is what the _monolithic script's "--wait" was there for.
  wait    = true
  timeout = var.timeout_seconds

  set = concat([
    {
      # crds.enabled in current chart versions; the chart used to call this
      # installCRDs, and passing the old name silently installs nothing.
      name  = "crds.enabled"
      value = tostring(var.install_crds)
    },
    ],
    var.additional_set_values,
  )
}
