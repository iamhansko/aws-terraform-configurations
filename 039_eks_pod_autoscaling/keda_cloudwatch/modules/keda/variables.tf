variable "oidc_provider_arn" {
  type        = string
  description = "ARN of the cluster's IAM OIDC provider, the federated principal the operator's role trusts"
  validation {
    condition     = can(regex("^arn:aws:iam::[0-9]{12}:oidc-provider/", var.oidc_provider_arn))
    error_message = "oidc_provider_arn must be an IAM OIDC provider ARN."
  }
}
variable "oidc_issuer_host" {
  type        = string
  description = "The cluster's OIDC issuer URL with the scheme stripped, used as the prefix for the sub and aud condition keys in the trust policy"
  validation {
    condition     = can(regex("^oidc\\.eks\\.[a-z0-9-]+\\.amazonaws\\.com/id/[A-Z0-9]+$", var.oidc_issuer_host))
    error_message = "oidc_issuer_host must look like oidc.eks.<region>.amazonaws.com/id/<id>, with no scheme."
  }
}
variable "role_name" {
  type        = string
  default     = "keda-operator-role"
  description = "Name of the IAM role the KEDA operator assumes through IRSA"
  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_-]{1,64}$", var.role_name))
    error_message = "role_name must be 1-64 characters from the set IAM accepts for a role name."
  }
}
variable "iam_policy_arns" {
  type = list(string)
  default = [
    "arn:aws:iam::aws:policy/CloudWatchReadOnlyAccess",
  ]
  description = "Managed policies attached to the operator's role. CloudWatchReadOnlyAccess as the _monolithic template had it, because the only scaler in use here reads a CloudWatch metric. A scaler for another AWS service - SQS queue depth, DynamoDB - needs its own read permission adding here, and a missing one shows up as a ScaledObject whose metric never resolves rather than as an error at apply time"
  validation {
    condition     = alltrue([for arn in var.iam_policy_arns : can(regex("^arn:aws:iam::", arn))])
    error_message = "iam_policy_arns must contain valid IAM policy ARNs."
  }
}
variable "release_name" {
  type        = string
  default     = "keda"
  description = "Helm release name"
  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.release_name))
    error_message = "release_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "chart_repository" {
  type        = string
  default     = "https://kedacore.github.io/charts"
  description = "Chart repository URL"
  validation {
    condition     = can(regex("^(https?|oci)://", var.chart_repository))
    error_message = "chart_repository must be an http(s) or oci URL."
  }
}
variable "chart_version" {
  type        = string
  default     = "2.17.2"
  description = "Chart version, as the _monolithic template pinned it in KEDA_CHART_VERSION"
  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+", var.chart_version))
    error_message = "chart_version must be a semver version, e.g. 2.17.2."
  }
}
variable "namespace" {
  type        = string
  default     = "keda"
  description = "Namespace KEDA runs in. It is part of the service account subject in the trust policy, so changing it changes which pod can assume the role"
  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "create_namespace" {
  type        = bool
  default     = true
  description = "Whether helm creates the namespace, as the _monolithic template's --create-namespace did"
}
variable "service_account_name" {
  type        = string
  default     = "keda-operator"
  description = "Service account the chart annotates with the role ARN, and the subject the trust policy allows. This is the chart's own name for the operator's service account, so it is only changed together with a nameOverride"
  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$", var.service_account_name))
    error_message = "service_account_name must be a valid lowercase RFC 1123 subdomain."
  }
}
variable "irsa_audience" {
  type        = string
  default     = "sts.amazonaws.com"
  description = "Token audience for IRSA. It reaches the cluster as an annotation on the service account and is also asserted in the trust policy's aud condition, so the two have to agree"
  validation {
    condition     = length(var.irsa_audience) > 0
    error_message = "irsa_audience must not be empty."
  }
}
variable "timeout_seconds" {
  type        = number
  default     = 600
  description = "How long helm waits for the release to become ready"
  validation {
    condition     = var.timeout_seconds > 0
    error_message = "timeout_seconds must be positive."
  }
}
variable "additional_set_values" {
  type = list(object({
    name  = string
    value = string
    type  = optional(string)
  }))
  default     = []
  description = "Extra helm values appended to the set list. type is auto when omitted, and only auto or string are accepted - a caller with no way to force a string could not pass an annotation value (rules.md E-7)"
  validation {
    condition     = alltrue([for entry in var.additional_set_values : entry.type == null || contains(["auto", "string"], entry.type)])
    error_message = "additional_set_values type must be auto or string when set."
  }
}
