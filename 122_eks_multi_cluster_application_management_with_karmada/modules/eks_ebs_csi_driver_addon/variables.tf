variable "cluster_name" {
  type        = string
  description = "Name of the EKS cluster the addon is installed on. Also the cluster the Pod Identity association is scoped to, which is why this module needs no OIDC provider ARN at all"

  validation {
    condition     = length(var.cluster_name) > 0
    error_message = "cluster_name must not be empty."
  }
}
variable "role_name" {
  type        = string
  default     = null
  description = "Optional fixed name for the driver's IAM role. Null generates one from role_name_prefix, which is what lets this project be deployed twice in one account - the guidance installer's fixed AmazonEKS_EBS_CSI_DriverRole_<region>_<prefix> name did not. Set it only when something outside this configuration has to name the role, which is not the case here (rules.md I-2)"

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
  description = "Service account the addon's controller runs as, and the one the Pod Identity association binds to the role. Decided by the addon rather than by this module, so changing it does not rename anything - it only breaks the association"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$", var.service_account_name))
    error_message = "service_account_name must be a valid lowercase RFC 1123 subdomain."
  }
}
variable "iam_policy_arns" {
  type        = list(string)
  default     = ["arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"]
  description = "Managed policies attached to the driver's role, the same one the guidance installer attached with eksctl create iamserviceaccount. The AWS managed policy covers creating, attaching, deleting and snapshotting volumes the driver owns"

  validation {
    condition     = length(var.iam_policy_arns) > 0 && alltrue([for arn in var.iam_policy_arns : can(regex("^arn:aws:iam::", arn))])
    error_message = "iam_policy_arns must contain at least one valid IAM policy ARN."
  }
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
  description = "What EKS does on update when a field has been changed outside the addon. OVERWRITE, which is what the guidance installer's --force flag on eksctl create addon amounted to"

  validation {
    condition     = contains(["NONE", "OVERWRITE", "PRESERVE"], var.resolve_conflicts_on_update)
    error_message = "resolve_conflicts_on_update must be one of NONE, OVERWRITE or PRESERVE."
  }
}
