# The KubeRay operator, which is what makes a RayService object mean anything: it
# watches for them and builds the Ray cluster, the Serve applications and the
# head Service behind each one.
#
# A Helm release rather than `helm install` inside a shell script an SSM Association ran
# on the bastion (rules.md E-1). The _monolithic template also ran
# `kubectl create namespace kuberay-operator` first and then passed -n to helm without
# --create-namespace, so the namespace was created outside any release and left behind
# on uninstall.
resource "helm_release" "kuberay_operator" {
  name             = var.release_name
  repository       = var.chart_repository
  chart            = "kuberay-operator"
  version          = var.chart_version
  namespace        = var.namespace
  create_namespace = var.create_namespace

  # Holds the apply until the operator Deployment is Available. The _monolithic template
  # did not wait, so the RayService it applied moments later could reach the API server
  # before the CRD existed - which fails with "no matches for kind" rather than with
  # anything about ordering.
  wait    = true
  timeout = var.timeout_seconds

  set = concat([
    {
      name  = "replicas"
      value = tostring(var.replica_count)
    },
    {
      name  = "resources.requests.cpu"
      value = var.cpu_request
      # A quantity string. helm's inference would read "100m" as a string anyway, but
      # a bare "1" would become a number and the chart's template writes it straight
      # into the container spec, where a bare number is still valid - so this is left
      # to auto rather than forced (rules.md E-7).
    },
    {
      name  = "resources.requests.memory"
      value = var.memory_request
    },
    ],
    var.additional_set_values,
  )
}
