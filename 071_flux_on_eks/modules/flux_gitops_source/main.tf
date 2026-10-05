# The GitOps loop itself: a repository to watch, and an instruction for what to do with it.
#
# The _monolithic template produced these two objects with "flux create source git ... --export"
# and "flux create kustomization ... --export", wrote the YAML into a cloned repository, and
# pushed it - so the objects reached the cluster only because Flux had already been bootstrapped
# to reconcile that repository. Here they are declared directly, which means they are in state,
# appear in plan, and are removed on destroy (rules.md E-2/E-3).
#
# What is lost by declaring them rather than committing them: these two objects are not
# themselves under Git control, so the demo shows Flux reconciling a repository from Git rather
# than Flux reconciling its own configuration from Git. That second half is what "flux bootstrap"
# does, and it is still not what this project does.
#
# The module is instantiated twice by the root, which is why the credential arguments below are
# optional rather than required. Once for the upstream podinfo repository - public, read-only, no
# Secret - and once for a repository in the caller's own GitHub account, which is private and
# therefore needs one (rules.md B-4).
#
# Field names are the Kubernetes API's, unchanged from the YAML the flux CLI emits
# (rules.md E-3).
locals {
  # Credentials are optional, because the two repositories this module is pointed at are not
  # alike: the upstream podinfo repository is public and read-only, and a repository in the
  # caller's own account is private. Null for the first, set for the second (rules.md B-4).
  #
  # Decided from the username rather than the password, which the validation on git_password
  # guarantees is equivalent - the two have to be set together or left null together. The
  # difference is that git_password is marked sensitive, and a comparison against a sensitive
  # value is itself sensitive: deriving this from it would mark this local, then the Secret name
  # built from it, and then anything that named it. The failure lands a long way from here, as
  # "Output refers to sensitive values" on a root output that only contains a Kubernetes object
  # name.
  needs_credentials = var.git_username != null
  secret_name       = coalesce(var.secret_name, "${var.name}-auth")
}
# The credential the source controller clones with. Only created when one was given.
#
# basic-auth is what Flux's own bootstrap writes for an https remote, and the key names are fixed
# by the controller: username and password, nothing else. A GitHub token goes in password, and the
# username is unused by GitHub but must be present.
#
# The token is in this manifest, so it is in the Terraform state and in the cluster. That is
# unavoidable for an https source: the controller has to be able to read it. What is avoidable is
# it also being in a plan, which is why the variable is marked sensitive - that propagates into
# yaml_body and Terraform redacts the whole attribute.
resource "kubectl_manifest" "git_credentials" {
  count = local.needs_credentials ? 1 : 0

  sensitive_fields = ["stringData.password"]

  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Secret"
    type       = "Opaque"
    metadata = {
      name      = local.secret_name
      namespace = var.namespace
    }
    # stringData rather than data, so the values are not base64 in this configuration. The API
    # server encodes them on the way in.
    stringData = {
      username = var.git_username
      password = var.git_password
    }
  })
}
resource "kubectl_manifest" "git_repository" {
  yaml_body = yamlencode({
    apiVersion = "source.toolkit.fluxcd.io/v1"
    kind       = "GitRepository"
    metadata = {
      name      = var.name
      namespace = var.namespace
    }
    spec = merge(
      {
        # How often the source controller looks for a new commit. This, not the Kustomization's
        # interval, is the delay between a push and the cluster noticing.
        interval = var.source_interval
        url      = var.url
        ref = {
          branch = var.branch
        }
      },
      # Omitted entirely for a public repository rather than set to an empty name, which the
      # controller would read as a Secret it cannot find (rules.md B-4).
      local.needs_credentials ? { secretRef = { name = local.secret_name } } : {},
    )
  })

  # secretRef names the Secret by a literal string rather than by reference, so nothing else tells
  # Terraform the Secret has to exist first. A GitRepository whose Secret is missing does not fail
  # at apply - it goes Ready=False with an authentication error, which reads like a bad token
  # (rules.md D-1).
  depends_on = [kubectl_manifest.git_credentials]
}
resource "kubectl_manifest" "kustomization" {
  yaml_body = yamlencode({
    apiVersion = "kustomize.toolkit.fluxcd.io/v1"
    kind       = "Kustomization"
    metadata = {
      name      = var.name
      namespace = var.namespace
    }
    spec = merge(
      {
        interval      = var.kustomization_interval
        retryInterval = var.retry_interval
        # Only meaningful with wait: true - it is how long the controller gives the applied
        # objects to become healthy before it calls the reconciliation failed.
        timeout = var.health_check_timeout
        path    = var.path
        # Without this, Git is the source of truth for what exists but not for what does not: an
        # object deleted from the repository stays in the cluster forever.
        prune = var.prune
        # Ready reflects the health of what was applied rather than merely that it was accepted.
        wait = var.wait_for_health
        sourceRef = {
          kind = "GitRepository"
          name = var.name
        }
      },
      # Omitted rather than set to a namespace, when the repository holds manifests that declare
      # their own. Setting it would rewrite them all into one namespace, which for Flux's own
      # custom resources means moving them out of the namespace the controllers watch
      # (rules.md B-4).
      var.target_namespace == null ? {} : { targetNamespace = var.target_namespace },
    )
  })

  # sourceRef names the GitRepository by a literal string rather than by reference, so nothing
  # else tells Terraform it has to exist first (rules.md D-1). A Kustomization whose source is
  # missing does not fail - it waits, with a Ready=False condition that says the source is not
  # found, which reads like a network problem.
  depends_on = [kubectl_manifest.git_repository]
}
