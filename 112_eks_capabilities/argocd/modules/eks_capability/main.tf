# An EKS Capability: an AWS-managed installation of ACK, kro or Argo CD on the cluster, plus the
# IAM role AWS assumes to run it.
#
# Both in one module because neither is useful alone - the capability requires a role whose trust
# policy names capabilities.eks.amazonaws.com, and a role with that trust and no capability is a
# role nothing can assume. The same reasoning that keeps a controller's IAM role next to its Helm
# release (rules.md C-2).
#
# The _monolithic template created the role and stopped. Each of its three variants differed from
# the others by exactly one IAM role name - ack_role, argocd_role, kro_role - and none of them
# created a capability, installed a controller, or applied a single Kubernetes object. The cluster
# came up with a role attached to nothing, and the variant names described an intent rather than a
# configuration.
resource "aws_iam_role" "capability" {
  name_prefix = "${substr(var.name, 0, 28)}-cap-"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        # capabilities.eks.amazonaws.com, which is the service principal for EKS Capabilities -
        # not pods.eks.amazonaws.com and not the cluster's OIDC provider. The capability runs
        # outside the cluster's own identity plumbing: AWS operates it and assumes this role to do
        # so, which is why there is no service account and no Pod Identity association here.
        Service = "capabilities.eks.amazonaws.com"
      }
      # TagSession as well as AssumeRole. The service attaches session tags identifying the
      # capability, and without this action the exchange fails with an error about tagging rather
      # than about trust - which is not where anyone looks first.
      Action = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "capability" {
  for_each   = toset(var.iam_policy_arns)
  role       = aws_iam_role.capability.name
  policy_arn = each.value
}

# A pause between creating the role and handing it to EKS, because IAM is eventually consistent and
# CreateCapability validates the trust policy as its first act.
#
# Without this the apply fails on a role whose trust policy is byte-for-byte the one the EKS
# documentation requires:
#
#   InvalidParameterException: The trust policy for the provided role is invalid. The policy must
#   include sts:AssumeRole and sts:TagSession actions granting access to the AWS service
#   capabilities.eks.amazonaws.com
#
# The message describes the policy, so it reads as a configuration error and sends the reader to the
# one place that is already correct. What it actually reports is that EKS could not see the trust
# policy yet: CreateRole returns before the document has propagated to the services that read it,
# and the capability is created in the same graph walk milliseconds later. The same race is why the
# AWS provider retries Lambda's "the role defined for the function cannot be assumed by Lambda" and
# the equivalent errors on ECS and Backup; aws_eks_capability is new enough to have no such retry,
# so the wait has to be in the configuration.
#
# The attachments are in depends_on rather than only the role, and that is also why they are not
# enough on their own: for kro iam_policy_arns is empty, so for_each produces zero instances and the
# capability's old depends_on on them ordered it after nothing at all. A variant with policies
# attached gets one extra API round trip out of it - about a second, which this race wins anyway.
# Both variants failed identically.
#
# Why a timer. There is no API that answers "has this role propagated": GetRole returns the document
# immediately from the endpoint that just wrote it, which is precisely the read that does not predict
# what EKS sees. rules.md D-5 rejects timers in place of a completion signal and that still holds
# wherever a signal exists - the marker files on the workbench are that argument. This is a case
# where none does, as with the Karmada registration wait in 122.
resource "time_sleep" "role_propagation" {
  create_duration = "${var.role_propagation_wait_seconds}s"

  # Waits again if the role is replaced rather than being a one-off that later applies skip. The
  # role has name_prefix, so any change that forces a new name produces a new role whose trust
  # policy has to propagate on its own.
  triggers = {
    role_arn = aws_iam_role.capability.arn
  }

  depends_on = [
    aws_iam_role.capability,
    aws_iam_role_policy_attachment.capability,
  ]
}

resource "aws_eks_capability" "capability" {
  cluster_name    = var.cluster_name
  capability_name = var.name
  type            = var.type
  role_arn        = aws_iam_role.capability.arn

  # RETAIN is the only value the API accepts today, so it is stated rather than defaulted: it means
  # deleting the capability leaves the Kubernetes objects it created behind. For ACK and kro that
  # matters - the custom resources those capabilities reconcile are the interface to real AWS
  # resources, and removing them would be a delete of whatever they represent.
  delete_propagation_policy = var.delete_propagation_policy

  # Only for Argo CD, which is the one type that takes configuration. ACK and kro take none, and
  # the block is omitted entirely for them rather than emitted empty (rules.md B-4).
  dynamic "configuration" {
    for_each = var.argo_cd_configuration == null ? [] : [var.argo_cd_configuration]
    content {
      argo_cd {
        namespace = configuration.value.namespace

        # Single sign-on through IAM Identity Center, which is not optional: Argo CD as a capability
        # supports no local users, and the provider marks this block required inside argo_cd. Its
        # instance ARN comes from the caller, because Identity Center is an account-level thing this
        # module has no business looking up (rules.md B-6).
        aws_idc {
          idc_instance_arn = configuration.value.idc_instance_arn
          # Null when the instance is in the same region as the cluster, which is the usual case and
          # what the provider omits. An instance ARN carries no region of its own, so a cluster in a
          # different region from the instance needs this to resolve it at all.
          idc_region = configuration.value.idc_region
        }

        # Reachable only through VPC endpoints when the caller names some. Left empty the Argo CD
        # server is reachable over the internet, which is the default and what this demo uses.
        dynamic "network_access" {
          for_each = length(configuration.value.vpce_ids) > 0 ? [configuration.value.vpce_ids] : []
          content {
            vpce_ids = network_access.value
          }
        }

        # Who gets which Argo CD role. Keyed by the role name, with the Identity Center identities
        # that map to it - an Argo CD with SSO on and no mapping is an Argo CD nobody can log in
        # to, which is not an error anywhere.
        dynamic "rbac_role_mapping" {
          for_each = configuration.value.rbac_role_mappings
          content {
            role = rbac_role_mapping.key
            dynamic "identity" {
              for_each = rbac_role_mapping.value
              content {
                id   = identity.value.id
                type = identity.value.type
              }
            }
          }
        }
      }
    }
  }

  tags = var.tags

  # The role has to carry its policies, and its trust policy has to have propagated, before AWS
  # assumes it to install anything. role_arn referencing the role orders this after neither: not
  # after the attachments, so a capability can start with a role that cannot call anything and fail
  # partway through its own installation, and not after the wait, which is what keeps CreateCapability
  # from validating a trust policy EKS cannot see yet (rules.md D-1). The wait depends on the
  # attachments in turn, so naming it here keeps both edges.
  depends_on = [time_sleep.role_propagation]
}
