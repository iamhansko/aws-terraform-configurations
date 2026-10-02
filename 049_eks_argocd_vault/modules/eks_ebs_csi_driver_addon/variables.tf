variable "cluster_name" {
  type        = string
  description = "Name of the EKS cluster to install the aws-ebs-csi-driver addon into"

  validation {
    condition     = length(var.cluster_name) > 0
    error_message = "cluster_name must not be empty."
  }
}
variable "oidc_provider_arn" {
  type        = string
  description = "ARN of the cluster's IAM OIDC provider, used as the Federated principal in the driver's IRSA trust policy"

  validation {
    condition     = can(regex("^arn:aws:iam::", var.oidc_provider_arn))
    error_message = "oidc_provider_arn must be a valid IAM OIDC provider ARN."
  }
}
variable "oidc_issuer_host" {
  type        = string
  description = "Cluster OIDC issuer URL without the https:// scheme, used in the trust policy's sub/aud condition keys"

  validation {
    condition     = length(var.oidc_issuer_host) > 0 && !can(regex("^https://", var.oidc_issuer_host))
    error_message = "oidc_issuer_host must be non-empty and must not include the https:// scheme."
  }
}
variable "role_name" {
  type        = string
  default     = null
  description = "Optional fixed name for the driver's IAM role. Null lets AWS generate one, which is what allows this project to be deployed twice in one account - IAM role names are account-wide, so a fixed name collides on the second copy"

  validation {
    condition     = var.role_name == null || can(regex("^[a-zA-Z0-9+=,.@_-]{1,64}$", var.role_name))
    error_message = "role_name must be 64 characters or fewer of the characters IAM accepts for a role name, or null."
  }
}
variable "namespace" {
  type        = string
  default     = "kube-system"
  description = "Namespace the driver's service account lives in. Baked into the trust policy's sub condition, so it has to match where the addon actually installs - EKS puts this addon in kube-system and that is not configurable"

  validation {
    condition     = length(var.namespace) > 0
    error_message = "namespace must not be empty."
  }
}
variable "service_account_name" {
  type        = string
  default     = "ebs-csi-controller-sa"
  description = "Service account the controller runs as, and the second half of the trust policy's sub condition. This is the name the addon creates; changing it breaks the trust relationship silently - volumes then stay Pending with an AccessDenied in the controller's log rather than any Terraform error"

  validation {
    condition     = length(var.service_account_name) > 0
    error_message = "service_account_name must not be empty."
  }
}
variable "iam_policy_arns" {
  type        = list(string)
  default     = ["arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"]
  description = "Managed policy ARNs attached to the driver's role. Without AmazonEBSCSIDriverPolicy the role exists, the addon installs and reports ACTIVE, and every PersistentVolumeClaim stays Pending - the reason is only in the ebs-csi-controller log. A list so a caller can add a KMS policy for encrypted volumes without editing this module (rules.md B-7)"

  validation {
    condition     = alltrue([for arn in var.iam_policy_arns : can(regex("^arn:aws:iam::", arn))])
    error_message = "iam_policy_arns must contain valid IAM policy ARNs."
  }
}
variable "addon_version" {
  type        = string
  default     = null
  description = "Specific aws-ebs-csi-driver addon version. When null, EKS picks the default version for the cluster's Kubernetes version"

  validation {
    condition     = var.addon_version == null || can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+-eksbuild\\.[0-9]+$", var.addon_version))
    error_message = "addon_version must look like v1.35.0-eksbuild.1, or null."
  }
}
variable "resolve_conflicts_on_create" {
  type        = string
  default     = "OVERWRITE"
  description = "How to resolve field value conflicts when creating an addon that is migrating from a pre-existing self-managed installation"

  validation {
    condition     = contains(["NONE", "OVERWRITE"], var.resolve_conflicts_on_create)
    error_message = "resolve_conflicts_on_create must be one of: NONE, OVERWRITE."
  }
}
variable "resolve_conflicts_on_update" {
  type        = string
  default     = "OVERWRITE"
  description = "How to resolve field value conflicts when updating the addon"

  validation {
    condition     = contains(["NONE", "OVERWRITE", "PRESERVE"], var.resolve_conflicts_on_update)
    error_message = "resolve_conflicts_on_update must be one of: NONE, OVERWRITE, PRESERVE."
  }
}
