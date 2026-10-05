# The Flux controllers: source, kustomize, helm and notification.
#
# The _monolithic template installed these with "curl -s https://fluxcd.io/install.sh | sudo
# bash" followed by "flux bootstrap github", from a shell on the bastion. Two things came out
# of that which are worth naming rather than repeating:
#
#   1. Nothing was in state. The controllers, their CRDs and the flux-system namespace did not
#      appear in any plan and were not removed by destroy - the cluster went away with them
#      still installed, which only looks harmless because the cluster went away.
#   2. "flux bootstrap github" does more than install. It creates a GitHub repository, commits
#      Flux's own manifests into it, and points Flux at that commit, so Flux manages itself from
#      Git. That is the right thing for a real cluster and it is not something a Helm release
#      does. This module installs the controllers; the repository half is left to the commands
#      in this project's README, where it is a deliberate step rather than a side effect of
#      terraform apply on somebody's GitHub account.
#
# The trade is explicit: with a chart, Flux does not manage its own upgrades from Git. What the
# project demonstrates - Flux reconciling a Git repository into the cluster, and noticing when
# that repository changes - works the same either way.
resource "helm_release" "flux" {
  name             = var.release_name
  repository       = var.chart_repository
  chart            = "flux2"
  version          = var.chart_version
  namespace        = var.namespace
  create_namespace = var.create_namespace
  # Holds the apply until the controllers are Available. That is not cosmetic here: the
  # GitRepository and Kustomization applied next are custom resources whose CRDs this release
  # installs, and applying them before the CRDs are established fails with "no matches for kind"
  # (rules.md D-2).
  wait    = true
  timeout = var.timeout_seconds

  set = concat([
    {
      name  = "imageReflectorController.create"
      value = tostring(var.install_image_automation)
    },
    {
      name  = "imageAutomationController.create"
      value = tostring(var.install_image_automation)
    },
    {
      name  = "notificationController.create"
      value = tostring(var.install_notification_controller)
    },
    ],
    var.additional_set_values,
  )
}
