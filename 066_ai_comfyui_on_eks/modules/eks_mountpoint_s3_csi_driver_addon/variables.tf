variable "cluster_name" {
  type        = string
  description = "Name of the EKS cluster to install the aws-mountpoint-s3-csi-driver addon into"
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
variable "namespace" {
  type        = string
  default     = "kube-system"
  description = "Namespace the addon's service account lives in. Must match where EKS installs the addon, since it is baked into the IRSA trust policy's sub condition"
  validation {
    condition     = length(var.namespace) > 0
    error_message = "namespace must not be empty."
  }
}
variable "service_account_name" {
  type        = string
  default     = "s3-csi-driver-sa"
  description = "Service account name the Mountpoint S3 CSI driver runs as. Fixed by the addon; changing it breaks the IRSA trust policy's sub condition"
  validation {
    condition     = length(var.service_account_name) > 0
    error_message = "service_account_name must not be empty."
  }
}
variable "bucket_arns" {
  type        = list(string)
  description = "ARNs of the buckets the driver may mount. Scoped explicitly rather than granting s3:* on every bucket: the driver's credentials are whatever this role allows, so a pod mounting a volume can reach exactly these buckets and nothing else. Injected as ARNs so the module never looks the buckets up itself (rules.md B-6)"
  validation {
    condition     = length(var.bucket_arns) > 0
    error_message = "bucket_arns must contain at least one bucket ARN."
  }
  validation {
    condition     = alltrue([for arn in var.bucket_arns : can(regex("^arn:aws:s3:::", arn))])
    error_message = "bucket_arns must contain valid S3 bucket ARNs (e.g. arn:aws:s3:::my-bucket)."
  }
}
variable "allow_delete" {
  type        = bool
  default     = true
  description = "Whether the driver's IAM policy grants s3:DeleteObject. Mountpoint also needs the allow-delete mount option before a pod can actually unlink files, so both have to agree - the policy alone does not enable deletion, and the mount option alone fails with AccessDenied"
}
variable "addon_version" {
  type        = string
  default     = null
  description = "Specific aws-mountpoint-s3-csi-driver addon version (e.g. v2.1.0-eksbuild.1). When null, EKS picks the default version for the cluster's Kubernetes version"
  validation {
    condition     = var.addon_version == null || can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+-eksbuild\\.[0-9]+$", var.addon_version))
    error_message = "addon_version must look like v2.1.0-eksbuild.1, or null."
  }
}
variable "configuration_values" {
  type        = string
  default     = null
  description = "Optional addon configuration as a JSON string, passed through to the addon's configuration_values. Left null by default so EKS applies its own defaults: the JSON schema differs per addon and per version, and an unrecognised key is only rejected at apply time. Confirm a value against 'aws eks describe-addon-configuration --addon-name aws-mountpoint-s3-csi-driver --addon-version <version>' before setting it (rules.md B-4/E-5)"
  validation {
    condition     = var.configuration_values == null || can(jsondecode(var.configuration_values))
    error_message = "configuration_values must be a valid JSON string, or null."
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
