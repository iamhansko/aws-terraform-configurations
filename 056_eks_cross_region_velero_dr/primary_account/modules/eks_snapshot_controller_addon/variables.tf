variable "cluster_name" {
  type        = string
  description = "Name of the EKS cluster the addon is installed on"

  validation {
    condition     = length(var.cluster_name) > 0
    error_message = "cluster_name must not be empty."
  }
}
variable "addon_version" {
  type        = string
  default     = null
  description = "Addon version. Null lets EKS pick the default for the cluster's Kubernetes version, which is what the _monolithic template effectively got by cloning the upstream default branch - except that this one is at least a version EKS has tested against this Kubernetes release. Pin it (aws eks describe-addon-versions --addon-name snapshot-controller) when the CRD schema matters, because a major version of the CRDs is not something to take by surprise"

  validation {
    condition     = var.addon_version == null || can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+-eksbuild\\.[0-9]+$", var.addon_version))
    error_message = "addon_version must look like v8.6.0-eksbuild.8, or null to let EKS choose."
  }
}
variable "resolve_conflicts_on_create" {
  type        = string
  default     = "OVERWRITE"
  description = "What EKS does when the addon's objects already exist at create time. OVERWRITE rather than NONE, because the VolumeSnapshot CRDs are exactly the kind of thing a previous hand-run kubectl left behind - and with NONE the addon create fails on them instead of adopting them"

  validation {
    condition     = contains(["NONE", "OVERWRITE"], var.resolve_conflicts_on_create)
    error_message = "resolve_conflicts_on_create must be either NONE or OVERWRITE."
  }
}
variable "resolve_conflicts_on_update" {
  type        = string
  default     = "OVERWRITE"
  description = "What EKS does on update when a field has been changed outside the addon, as the _monolithic template set on every addon"

  validation {
    condition     = contains(["NONE", "OVERWRITE", "PRESERVE"], var.resolve_conflicts_on_update)
    error_message = "resolve_conflicts_on_update must be one of NONE, OVERWRITE or PRESERVE."
  }
}
