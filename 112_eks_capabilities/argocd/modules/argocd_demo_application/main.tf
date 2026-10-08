# One Argo CD Application, so there is something for the capability's Argo CD to reconcile. The
# _monolithic template created the capability and stopped, which left an Argo CD with no
# applications - a UI nobody could log in to showing nothing.
#
# Declared as a kubectl_manifest rather than applied from the workbench so it is in Terraform state
# and `terraform destroy` removes it. That ordering is what matters: Argo CD deletes the objects it
# deployed when the Application goes away, and if the capability were removed first the Application
# would keep its finalizer with no controller to clear it and the delete would hang
# (rules.md E-1/E-3/D-4).
resource "kubectl_manifest" "application" {
  yaml_body = yamlencode({
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name = var.name
      # The capability's own namespace, not the namespace the workload lands in. Argo CD only reads
      # Applications from where it runs, so an Application anywhere else is simply ignored - no
      # error, no event.
      namespace = var.argocd_namespace
    }
    spec = {
      project = var.project
      source = {
        repoURL = var.repo_url
        path    = var.path
        # HEAD, as the upstream example repository has no releases to pin to. Anything longer lived
        # than a demo should name a commit here, because automated sync means a push to that
        # repository changes this cluster.
        targetRevision = var.target_revision
      }
      destination = {
        # in-cluster, the target Argo CD registers for its own cluster. A remote cluster would need
        # an access entry for the capability role over there as well.
        server    = "https://kubernetes.default.svc"
        namespace = var.destination_namespace
      }
      syncPolicy = {
        # Automated, so the Application converges without anyone opening the UI - which is the only
        # way to see the capability working in an account where nobody has signed in yet.
        automated = {
          prune    = var.prune
          selfHeal = var.self_heal
        }
        # The destination namespace is not declared anywhere in this configuration, so Argo CD has
        # to create it. Without this the Application reports a sync error about a missing namespace.
        syncOptions = ["CreateNamespace=true"]
      }
    }
  })

  # The Application CRD does not exist until the capability has installed Argo CD, and a manifest
  # whose kind is unregistered fails with "no matches for kind" rather than waiting for it
  # (rules.md D-4).
  depends_on = [var.capability_dependency]
}
