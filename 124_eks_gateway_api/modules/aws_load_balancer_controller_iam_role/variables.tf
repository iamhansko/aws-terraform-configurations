variable "oidc_provider_arn" {
  type        = string
  description = "ARN of the cluster's IAM OIDC provider, which this role's trust policy federates with"

  validation {
    condition     = can(regex("^arn:aws:iam::[0-9]{12}:oidc-provider/", var.oidc_provider_arn))
    error_message = "oidc_provider_arn must be an IAM OIDC provider ARN (e.g. arn:aws:iam::123456789012:oidc-provider/oidc.eks.ap-northeast-2.amazonaws.com/id/EXAMPLE)."
  }
}
variable "oidc_issuer_host" {
  type        = string
  description = "The cluster's OIDC issuer URL with the https:// scheme stripped, used as the prefix of the :sub and :aud condition keys"

  validation {
    condition     = can(regex("^oidc\\.eks\\.", var.oidc_issuer_host)) && !startswith(var.oidc_issuer_host, "https://")
    error_message = "oidc_issuer_host must be the issuer host without a scheme (e.g. oidc.eks.ap-northeast-2.amazonaws.com/id/EXAMPLE). A value with https:// still produces a syntactically valid trust policy that no token can ever satisfy."
  }
}
variable "namespace" {
  type        = string
  default     = "kube-system"
  description = "Namespace the controller's service account lives in, as the _monolithic template installed the chart into. Named in the trust policy's :sub condition, so it has to match the namespace the chart is actually installed into"

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a valid Kubernetes namespace name."
  }
}
variable "service_account_name" {
  type        = string
  default     = "aws-load-balancer-controller"
  description = "Name of the service account the controller runs as, as the _monolithic template's --set serviceAccount.name had it. Named in the trust policy's :sub condition, so it has to match the service account the chart creates"

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$", var.service_account_name))
    error_message = "service_account_name must be a valid Kubernetes service account name."
  }
}
variable "role_name_prefix" {
  type        = string
  default     = "eks-alb-controller-"
  description = "Prefix for the generated role name. A prefix rather than a fixed name so two copies of this project in one account do not collide on it - the chart is told the ARN this module outputs, so nothing depends on the name being predictable"

  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_-]{1,32}$", var.role_name_prefix))
    error_message = "role_name_prefix must be 32 characters or fewer from the set IAM accepts for a role name, leaving room for the generated suffix."
  }
}
