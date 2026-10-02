# Vault, from helm_release rather than the "helm install vault hashicorp/vault ..." line an
# SSM Association ran on the bastion (rules.md E-1).
#
# The one thing this module does NOT do is initialise Vault. "vault operator init" is a
# one-time imperative operation that mints the unseal key and the root token, and there is no
# Terraform resource for it: the vault provider needs an already-initialised Vault, so driving
# it from here is circular. That step stays in an SSM Association in the root, which is the
# documented exception to rules.md E-1 for this project - see the comment on
# aws_ssm_association.vault_bootstrap there.
#
# values rather than a long list of escaped set entries: annotation keys contain dots that
# helm's --set treats as path separators, and the _monolithic template's escaping of them is
# exactly where its bug lived (see below). A yamlencode'd object has no escaping to get wrong
# and renders the nesting the chart actually documents.
locals {
  values = {
    server = {
      # server.ingress, NOT a top-level ingress key. The chart has no top-level "ingress"
      # value at all, so the _monolithic template's
      #   --set ingress.enabled=true --set ingress.ingressClassName=alb --set ingress.annotations...
      # was accepted by helm and discarded by the chart. No Ingress was ever created, which
      # means the pre-created ALB tagged ingress.k8s.aws/stack=vault/vault had nothing to be
      # adopted from and Vault's UI was unreachable through it - with no error anywhere
      # (rules.md G-3).
      ingress = {
        enabled          = var.ingress_enabled
        ingressClassName = var.ingress_class_name
        annotations      = var.ingress_annotations
        hosts            = var.ingress_hosts
      }
      # The chart's default is a 10Gi PVC, and two things have to be true for it to bind.
      #
      # A driver: the EBS CSI driver addon, which this project installs.
      #
      # A StorageClass: which the addon does NOT create. The chart leaves storageClass unset by
      # default, so the claim names no class and falls back to whichever class is annotated
      # default - and on a fresh EKS cluster at Kubernetes 1.33 none is. The only class present
      # is the built-in gp2, whose in-tree kubernetes.io/aws-ebs provisioner was removed in 1.23
      # and which carries no default annotation. The claim then resolves to nothing, vault-0 sits
      # Pending with "pod has unbound immediate PersistentVolumeClaims", and the bootstrap
      # association in the root fails waiting for a pod that can never start.
      #
      # So the class is named here explicitly rather than left to the default annotation. The
      # name arrives from the module that creates the class (rules.md B-5), which also makes the
      # release wait for it.
      dataStorage = {
        enabled      = var.data_storage_enabled
        size         = var.data_storage_size
        storageClass = var.storage_class
      }
    }
  }
}
resource "helm_release" "vault" {
  name             = var.release_name
  repository       = var.chart_repository
  chart            = "vault"
  version          = var.chart_version
  namespace        = var.namespace
  create_namespace = true
  # False, and this one is not a preference - a true here cannot ever be satisfied.
  #
  # helm --wait waits for the StatefulSet's pod to be Ready, and the chart's readiness probe is
  # `vault status -tls-skip-verify`, whose exit code *is* the seal status: 0 unsealed, 1 error,
  # 2 sealed. A freshly installed Vault is uninitialised and sealed, so the probe fails, the pod
  # never becomes Ready, and the install runs to its timeout.
  #
  # What unseals it is the bootstrap association in the root, which is ordered after this release.
  # So waiting here is a deadlock: the release waits for something only a later step can do. The
  # first apply spent the whole timeout and left the release in `failed` state, and every apply
  # after that failed immediately with "cannot re-use a name that is still in use" - a message
  # about the second attempt that says nothing about the first (rules.md E-7).
  wait    = var.wait_for_release
  timeout = var.timeout_seconds

  values = [yamlencode(local.values)]

  set = var.additional_set_values
}
