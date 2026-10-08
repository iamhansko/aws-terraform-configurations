variable "name" {
  type        = string
  default     = "vscode"
  description = "Prefix for the IAM role name"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-_]{0,30}$", var.name))
    error_message = "name must be letters, digits, hyphens and underscores, starting with a letter or digit."
  }
}

variable "cluster_name" {
  type        = string
  description = "Name of the EKS cluster the pod runs on"

  validation {
    condition     = length(var.cluster_name) > 0
    error_message = "cluster_name must not be empty."
  }
}

variable "namespace" {
  type        = string
  default     = "default"
  description = "Namespace of the service account the role is bound to"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a valid lowercase RFC 1123 label."
  }
}

variable "service_account_name" {
  type        = string
  default     = "vscode"
  description = "Service account the role is bound to. Taken from the module that creates it rather than restated, so a rename cannot silently unbind the role (rules.md B-5)"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.service_account_name))
    error_message = "service_account_name must be a valid lowercase RFC 1123 label."
  }
}

variable "iam_policy_arns" {
  type        = list(string)
  default     = ["arn:aws:iam::aws:policy/AdministratorAccess"]
  description = "Managed policies attached to the role. A list rather than repeated attachment resources, so the caller can change the set without editing this module (rules.md B-7)"

  validation {
    condition     = alltrue([for arn in var.iam_policy_arns : can(regex("^arn:aws:iam::", arn))])
    error_message = "iam_policy_arns must contain valid IAM policy ARNs."
  }
}

variable "identity_mode" {
  type        = string
  default     = "pod_identity"
  description = <<-DESC
    Which mechanism binds the role to the service account: "pod_identity" or "irsa".

    Not a style choice. Pod Identity is delivered by an agent DaemonSet, so it cannot run on a
    Fargate-only cluster - that variant has to use IRSA. On a cluster with nodes, Pod Identity is simpler:
    no annotation on the service account, and no trust policy tied to the cluster's OIDC issuer, which
    means the role survives a cluster rebuild.

    An explicit mode rather than "irsa when oidc_provider_arn is set", because that ARN comes from the
    cluster module and is unknown during plan - a count derived from it fails before anything is created
    (rules.md B-8).
  DESC

  validation {
    condition     = contains(["pod_identity", "irsa"], var.identity_mode)
    error_message = "identity_mode must be either pod_identity or irsa."
  }
}

variable "oidc_provider_arn" {
  type        = string
  default     = null
  description = "ARN of the cluster's IAM OIDC provider, used as the Federated principal of the trust policy. Required when identity_mode is irsa and ignored otherwise"

  validation {
    condition     = var.oidc_provider_arn == null || can(regex("^arn:aws:iam::[0-9]+:oidc-provider/", var.oidc_provider_arn))
    error_message = "oidc_provider_arn must be an IAM OIDC provider ARN, or null when identity_mode is pod_identity."
  }

  validation {
    # The pair, not either value alone. An IRSA role with no Federated principal is rejected by IAM,
    # and the message names the policy document rather than the missing input (rules.md B-1).
    condition     = var.identity_mode != "irsa" || var.oidc_provider_arn != null
    error_message = "oidc_provider_arn is required when identity_mode is irsa, because it is the Federated principal the trust policy names."
  }
}

variable "oidc_issuer_host" {
  type        = string
  default     = null
  description = "Host part of the cluster's OIDC issuer URL, used as the prefix of the trust policy's condition keys. Required when identity_mode is irsa"

  validation {
    condition     = var.oidc_issuer_host == null || can(regex("^oidc\\.eks\\.[a-z0-9-]+\\.amazonaws\\.com/id/[A-Z0-9]+$", var.oidc_issuer_host))
    error_message = "oidc_issuer_host must look like oidc.eks.<region>.amazonaws.com/id/<hash> - the issuer URL without its https:// scheme, or null."
  }

  validation {
    # An IRSA trust policy with no issuer host produces condition keys like ":sub", which match nothing
    # and fail as an access denial rather than as a configuration error (rules.md B-1).
    condition     = var.identity_mode != "irsa" || var.oidc_issuer_host != null
    error_message = "oidc_issuer_host is required when identity_mode is irsa, because it forms the prefix of the trust policy's sub and aud condition keys."
  }
}
