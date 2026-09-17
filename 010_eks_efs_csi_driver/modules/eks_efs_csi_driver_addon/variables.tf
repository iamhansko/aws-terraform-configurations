variable "cluster_name" {
  type        = string
  description = "Name of the EKS cluster to install the aws-efs-csi-driver addon into"
  validation {
    condition     = length(var.cluster_name) > 0
    error_message = "cluster_name must not be empty."
  }
}
variable "oidc_provider_arn" {
  type        = string
  description = "ARN of the cluster's IAM OIDC provider, used as the Federated principal in the controller's IRSA trust policy"
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
variable "namespace" {
  type        = string
  default     = "kube-system"
  description = "Namespace the addon's controller service account lives in. Must match where EKS installs the addon, since it is baked into the IRSA trust policy's sub condition"
  validation {
    condition     = length(var.namespace) > 0
    error_message = "namespace must not be empty."
  }
}
variable "service_account_name" {
  type        = string
  default     = "efs-csi-controller-sa"
  description = "Service account name the EFS CSI controller runs as. Fixed by the addon; changing it breaks the IRSA trust policy's sub condition"
  validation {
    condition     = length(var.service_account_name) > 0
    error_message = "service_account_name must not be empty."
  }
}
variable "addon_version" {
  type        = string
  default     = null
  description = "Specific aws-efs-csi-driver addon version (e.g. v2.1.14-eksbuild.1). When null, EKS picks the default version for the cluster's Kubernetes version, which avoids pinning to a build a newer cluster no longer supports"
  validation {
    condition     = var.addon_version == null || can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+-eksbuild\\.[0-9]+$", var.addon_version))
    error_message = "addon_version must look like v2.1.14-eksbuild.1, or null."
  }
}
variable "configuration_values" {
  type        = string
  default     = null
  description = "Optional addon configuration as a JSON string, passed through to the addon's configuration_values. Left null by default so EKS applies its own defaults: the JSON schema differs per addon and per version, and an unrecognised key is only rejected at apply time. Confirm a value against 'aws eks describe-addon-configuration --addon-name aws-efs-csi-driver --addon-version <version>' before setting it (rules.md B-4/E-5)"
  validation {
    condition     = var.configuration_values == null || can(jsondecode(var.configuration_values))
    error_message = "configuration_values must be a valid JSON string, or null."
  }
}
variable "iam_policy_arns" {
  type        = list(string)
  default     = ["arn:aws:iam::aws:policy/service-role/AmazonEFSCSIDriverPolicy"]
  description = "IAM managed policy ARNs attached to the EFS CSI controller's IRSA role. AmazonEFSCSIDriverPolicy is what lets the controller create and delete the access points that back dynamically provisioned volumes"
  validation {
    condition     = alltrue([for arn in var.iam_policy_arns : can(regex("^arn:aws:iam::", arn))])
    error_message = "iam_policy_arns must contain valid IAM policy ARNs."
  }
}
variable "resolve_conflicts_on_create" {
  type        = string
  default     = "OVERWRITE"
  description = "How to resolve field value conflicts when creating an addon that is migrating from a pre-existing self-managed installation (e.g. the efs-csi-controller manifest the _monolithic design applied by hand)"
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
