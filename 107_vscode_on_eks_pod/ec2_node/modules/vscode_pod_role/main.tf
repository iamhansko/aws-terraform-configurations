# The AWS identity the code-server pod runs as: an IAM role plus whatever wires it to the pod's
# service account.
#
# Two ways to do that, and which one is available is a property of the cluster rather than a
# preference. EKS Pod Identity is an agent addon running as a DaemonSet, so it needs a node to run
# on; a Fargate-only cluster has none and has to use IRSA, where the role trusts the cluster's OIDC
# provider and the service account carries an annotation naming the role. The caller decides by
# passing oidc_provider_arn or leaving it null.
#
# Both halves live in one module because neither is useful alone - a role with this trust policy and
# no association is a role nothing assumes, and an association naming a role that does not exist is
# rejected. Same reasoning that keeps a controller's IAM role beside its Helm release
# (rules.md C-2).
locals {
  # Driven by an explicit mode rather than by whether oidc_provider_arn happens to be null. That ARN
  # is the cluster module's output and unknown at plan time, so a count derived from it fails with
  # "The count value depends on resource attributes that cannot be determined until apply". The same
  # rule as for_each keys: the shape of the configuration has to be known during plan, and only the
  # values inside it may be unknown (rules.md B-8).
  use_irsa = var.identity_mode == "irsa"
}

resource "aws_iam_role" "pod" {
  name_prefix = "${substr(var.name, 0, 24)}-pod-"

  # Two statements written as two conditional lists concatenated rather than one ternary. A ternary
  # between the two objects is rejected: their Action and Condition attributes have different types,
  # and Terraform requires both branches of a conditional to agree.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      local.use_irsa ? [{
        Effect    = "Allow"
        Principal = { Federated = var.oidc_provider_arn }
        Action    = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            # Both conditions, not just sub. Without the aud check the role can be assumed by any
            # token the provider issued; without the sub check, by any service account in the
            # cluster.
            "${var.oidc_issuer_host}:sub" = "system:serviceaccount:${var.namespace}:${var.service_account_name}"
            "${var.oidc_issuer_host}:aud" = "sts.amazonaws.com"
          }
        }
      }] : [],
      local.use_irsa ? [] : [{
        Effect    = "Allow"
        Principal = { Service = "pods.eks.amazonaws.com" }
        # TagSession as well as AssumeRole. Pod Identity attaches session tags identifying the
        # cluster and the pod, and without this action the exchange fails with an error about
        # tagging rather than about trust.
        Action = ["sts:AssumeRole", "sts:TagSession"]
      }],
    )
  })
}

resource "aws_iam_role_policy_attachment" "pod" {
  for_each   = toset(var.iam_policy_arns)
  role       = aws_iam_role.pod.name
  policy_arn = each.value
}

# Only for Pod Identity. On a cluster without the agent this resource is accepted and simply never
# takes effect, so it is left out rather than created and ignored (rules.md B-4).
resource "aws_eks_pod_identity_association" "pod" {
  count = local.use_irsa ? 0 : 1

  cluster_name    = var.cluster_name
  namespace       = var.namespace
  service_account = var.service_account_name
  role_arn        = aws_iam_role.pod.arn

  # The association has to find the role's policies already attached, and role_arn alone orders this
  # only after the role itself (rules.md D-1).
  depends_on = [aws_iam_role_policy_attachment.pod]
}
