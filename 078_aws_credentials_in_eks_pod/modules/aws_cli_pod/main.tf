locals {
  labels = {
    app = var.name
    # Not used by anything in Kubernetes. It is here so that a pod pulled out of "kubectl get pods -o
    # yaml" says which of the three mechanisms its cluster was built for - the three pods are otherwise
    # byte-for-byte identical, which is the point of the comparison and also what makes it easy to lose
    # track of which cluster you are looking at.
    "credential-mechanism" = var.credential_mechanism
  }
}
# The service account, and the one line that makes IRSA work.
#
# All three clusters get the same account. On the IRSA cluster it carries an eks.amazonaws.com/role-arn
# annotation and the pod's AWS SDK then exchanges a projected token for that role's credentials; on the
# Pod Identity cluster the same binding is an AWS-side association naming this account, and the account
# itself is unannotated; on the IMDS cluster there is no binding at all and the SDK falls through to the
# node's instance profile.
#
# The failure mode all three share is worth stating: a pod whose intended mechanism is misconfigured does
# not fail. It gets the node's credentials instead, quietly, and "aws sts get-caller-identity" is the only
# thing that says so - which is why this project's whole demo is that one command.
#
# The _monolithic template applied this account with kubectl and then added the annotation with a separate
# "kubectl annotate serviceaccount" call, so the annotated state existed in no file (rules.md E-1/E-5).
resource "kubectl_manifest" "service_account" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "ServiceAccount"
    metadata = merge(
      {
        name      = var.service_account_name
        namespace = var.namespace
        labels    = local.labels
      },
      # Omitted entirely rather than set empty when there is no role to name, which is the correct state
      # for two of the three clusters (rules.md B-4).
      var.role_arn_annotation == null ? {} : {
        annotations = {
          "eks.amazonaws.com/role-arn" = var.role_arn_annotation
        }
      },
    )
  })
}
# The pod. It runs nothing: the AWS CLI image with "tail -f /dev/null" as its command, so it stays up and
# can be exec'd into.
#
# Identical on all three clusters, deliberately. Nothing in this manifest names a role, a mechanism or a
# credential source - the pod asks the SDK for credentials and the SDK finds whatever the cluster has been
# arranged to give it. That is the comparison.
resource "kubectl_manifest" "pod" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Pod"
    metadata = {
      name      = var.name
      namespace = var.namespace
      labels    = local.labels
    }
    spec = {
      serviceAccountName = var.service_account_name
      # Stated rather than left to the default. False is what makes the IMDS case a real demonstration: a
      # pod on the host network reaches the node's metadata service at one hop, while a pod in its own
      # namespace needs the node's IMDS hop limit raised to two - which the node group module does, and
      # which is the setting that decides whether this mechanism works at all.
      hostNetwork                  = false
      dnsPolicy                    = "ClusterFirst"
      restartPolicy                = "Always"
      automountServiceAccountToken = var.automount_service_account_token
      containers = [{
        name    = var.name
        image   = var.image
        command = ["tail"]
        args    = ["-f", "/dev/null"]
      }]
    }
  })

  # serviceAccountName is a literal string rather than a reference, so nothing else tells Terraform the
  # account has to exist first (rules.md D-1). A pod naming a missing service account is rejected at
  # admission, which at least fails loudly - unlike the annotation being wrong.
  depends_on = [kubectl_manifest.service_account]
}
