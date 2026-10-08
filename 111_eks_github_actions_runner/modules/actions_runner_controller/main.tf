# Actions Runner Controller, and one runner scale set registered with GitHub.
#
# Two Helm releases and one Secret, all here because they are one component: the runner scale set's CRDs are
# installed by the controller chart, the Secret has to be in the runners' namespace, and none of the three is
# useful alone (rules.md C-2).
#
# The _monolithic template installed both charts with helm commands in EC2 user data, after an "exec bash"
# line that replaced the shell - so on a real boot neither ran. Even if they had, two things were wrong:
# githubConfigUrl contained a literal "UNSUPPORTED_REF_GitHubRepository" left behind by a CloudFormation
# resource that failed to convert, and the token was passed on a helm command line (rules.md E-1).
#
# Namespaces are declared rather than created by Helm's create_namespace, because the Secret has to exist in
# one of them before the release that reads it - and a namespace Helm owns is deleted with the release,
# taking the Secret with it.
resource "kubectl_manifest" "controller_namespace" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Namespace"
    metadata   = { name = var.controller_namespace }
  })
}
resource "kubectl_manifest" "runner_namespace" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Namespace"
    metadata   = { name = var.runner_namespace }
  })
}
# The credential, as a Secret the chart is pointed at by name.
#
# github_token is the key ARC looks for; the chart's githubConfigSecret can either be a map of values it turns
# into a Secret of its own, or the name of one that already exists. Naming an existing Secret is what keeps
# the token off a command line and out of the Helm release's stored values - a release's values are readable
# with helm get values by anyone who can reach the cluster.
resource "kubectl_manifest" "github_credentials" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Secret"
    type       = "Opaque"
    metadata = {
      name      = var.github_secret_name
      namespace = var.runner_namespace
    }
    stringData = {
      github_token = var.github_token
    }
  })

  # The manifest carries the token, so it must not be echoed into a plan or a log.
  sensitive_fields = ["stringData.github_token"]

  depends_on = [kubectl_manifest.runner_namespace]
}
resource "helm_release" "controller" {
  name       = var.controller_release_name
  repository = "oci://ghcr.io/actions/actions-runner-controller-charts"
  chart      = "gha-runner-scale-set-controller"
  version    = var.chart_version
  namespace  = var.controller_namespace
  # False: the namespace is a declared resource above, so Helm adopting it would make a release deletion remove
  # it as well.
  create_namespace = false
  # Waits for the controller's deployment to be Available, which is what the original's --wait did. It matters
  # here beyond tidiness: the runner scale set below is a custom resource this chart's CRDs define, so applying
  # it before the controller is up fails with "no matches for kind".
  wait    = true
  timeout = var.helm_timeout_seconds

  depends_on = [kubectl_manifest.controller_namespace]
}
resource "helm_release" "runner_set" {
  name             = var.runner_set_name
  repository       = "oci://ghcr.io/actions/actions-runner-controller-charts"
  chart            = "gha-runner-scale-set"
  version          = var.chart_version
  namespace        = var.runner_namespace
  create_namespace = false
  # Worth being precise about what this does and does not buy, because the comment here used to claim the
  # second thing and it is not true.
  #
  # It waits for this chart's own objects. The chart's substantive object is the AutoscalingRunnerSet custom
  # resource, and helm does not wait on custom resources - so this release reports success as soon as the CR is
  # accepted by the API server.
  #
  # It does not wait for the listener. The controller creates that afterwards, out of band, and only if GitHub
  # hands it a runner registration token. So a wrong URL, a missing repository or a token without the scope all
  # produce a green apply and a scale set that never runs anything; the reason stays in the controller's log.
  # The root's verify_runner_registration association is what turns that into a failed apply (rules.md D-2).
  wait    = true
  timeout = var.helm_timeout_seconds

  set = concat(
    [
      {
        name  = "githubConfigUrl"
        value = var.github_config_url
      },
      {
        # The Secret's name, not its contents. A string rather than a map is how the chart distinguishes "use
        # this existing Secret" from "create one from these values".
        name  = "githubConfigSecret"
        value = var.github_secret_name
        # Explicitly a string: the value is a Kubernetes object name, and helm's set infers types (rules.md E-7).
        type = "string"
      },
      {
        name  = "minRunners"
        value = tostring(var.min_runners)
      },
      {
        name  = "maxRunners"
        value = tostring(var.max_runners)
      },
    ],
    var.runner_group == null ? [] : [{
      name  = "runnerGroup"
      value = var.runner_group
      type  = "string"
    }],
    var.container_mode == "" ? [] : [{
      name  = "containerMode.type"
      value = var.container_mode
      type  = "string"
    }],
  )

  # The controller's CRDs define the AutoscalingRunnerSet this chart creates, and the Secret has to exist
  # before the listener starts. Neither is implied by anything in the arguments above (rules.md D-1).
  depends_on = [helm_release.controller, kubectl_manifest.github_credentials]
}
