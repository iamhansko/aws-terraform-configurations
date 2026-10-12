variable "cluster_name" {
  type        = string
  description = "Name of the EKS cluster the addon is installed on"

  validation {
    condition     = length(var.cluster_name) > 0
    error_message = "cluster_name must not be empty."
  }
}
variable "oidc_provider_arn" {
  type        = string
  description = "ARN of the cluster's IAM OIDC provider, the Federated principal in the driver role's trust policy"

  validation {
    condition     = can(regex("^arn:aws:iam::[0-9]{12}:oidc-provider/", var.oidc_provider_arn))
    error_message = "oidc_provider_arn must be a valid IAM OIDC provider ARN."
  }
}
variable "oidc_issuer_host" {
  type        = string
  description = "Cluster OIDC issuer URL without the https:// scheme, used as the prefix of the trust policy's sub and aud condition keys"

  validation {
    condition     = length(var.oidc_issuer_host) > 0 && !startswith(var.oidc_issuer_host, "https://")
    error_message = "oidc_issuer_host must be non-empty and must not include the https:// scheme."
  }
}
variable "role_name" {
  type        = string
  default     = null
  description = "Optional fixed name for the driver's IAM role. Null generates one from role_name_prefix, which is what lets this project be deployed twice in one account"

  validation {
    condition     = var.role_name == null || can(regex("^[a-zA-Z0-9+=,.@_-]{1,64}$", var.role_name))
    error_message = "role_name must be 1-64 characters of the set IAM accepts for a role name, or null."
  }
}
variable "role_name_prefix" {
  type        = string
  default     = "ebs-csi-driver-"
  description = "Prefix for the generated role name when role_name is null"

  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_-]{1,32}$", var.role_name_prefix))
    error_message = "role_name_prefix must be 1-32 characters of the set IAM accepts for a role name."
  }
}
variable "service_account_name" {
  type        = string
  default     = "ebs-csi-controller-sa"
  description = "Service account the addon's controller runs as in kube-system, and the one the role's trust policy names. Decided by the addon rather than by this module, so changing it does not rename anything - it only makes the trust policy name a service account that does not exist"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$", var.service_account_name))
    error_message = "service_account_name must be a valid lowercase RFC 1123 subdomain."
  }
}
variable "iam_policy_arns" {
  type        = list(string)
  default     = ["arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"]
  description = "Managed policies attached to the driver's role. The AWS managed policy is what the blueprint's attach_ebs_csi_policy rebuilt inline, and covers creating, attaching, deleting and snapshotting volumes the driver owns"

  validation {
    condition     = length(var.iam_policy_arns) > 0 && alltrue([for arn in var.iam_policy_arns : can(regex("^arn:aws:iam::", arn))])
    error_message = "iam_policy_arns must contain at least one valid IAM policy ARN."
  }
}
variable "grant_snapshot_tagging" {
  type        = bool
  default     = false
  description = "Whether to add ec2:CreateTags on volumes and snapshots the driver itself creates, scoped by the ec2:CreateAction condition. Off here: nothing in this project snapshots anything, and a permission granted for a workflow that does not exist is a permission nobody will remember to remove (rules.md A-5). Turn it on together with whatever takes the snapshots"
}
variable "addon_version" {
  type        = string
  default     = null
  description = "Addon version. Null lets EKS pick the default for the cluster's Kubernetes version"

  validation {
    condition     = var.addon_version == null || can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+-eksbuild\\.[0-9]+$", var.addon_version))
    error_message = "addon_version must look like v1.66.0-eksbuild.1, or null to let EKS choose."
  }
}
variable "resolve_conflicts_on_create" {
  type        = string
  default     = "OVERWRITE"
  description = "What EKS does when the addon's objects already exist at create time"

  validation {
    condition     = contains(["NONE", "OVERWRITE"], var.resolve_conflicts_on_create)
    error_message = "resolve_conflicts_on_create must be either NONE or OVERWRITE."
  }
}
variable "resolve_conflicts_on_update" {
  type        = string
  default     = "OVERWRITE"
  description = "What EKS does on update when a field has been changed outside the addon"

  validation {
    condition     = contains(["NONE", "OVERWRITE", "PRESERVE"], var.resolve_conflicts_on_update)
    error_message = "resolve_conflicts_on_update must be one of NONE, OVERWRITE or PRESERVE."
  }
}
