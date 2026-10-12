variable "cluster_name" {
  type        = string
  description = "Name of the EKS cluster to install the metrics-server addon into"

  validation {
    condition     = length(var.cluster_name) > 0
    error_message = "cluster_name must not be empty."
  }
}
variable "addon_version" {
  type        = string
  default     = null
  description = "Specific metrics-server addon version (e.g. v0.8.0-eksbuild.1). When null, EKS picks the default version for the cluster's Kubernetes version"

  validation {
    condition     = var.addon_version == null || can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+-eksbuild\\.[0-9]+$", var.addon_version))
    error_message = "addon_version must look like v0.8.0-eksbuild.1, or null."
  }
}
variable "replica_count" {
  type        = number
  default     = 1
  description = "Number of metrics-server replicas. More than one requires the high-availability chart settings, so the default keeps a single replica"

  validation {
    condition     = var.replica_count > 0
    error_message = "replica_count must be greater than zero."
  }
}
variable "resolve_conflicts_on_create" {
  type        = string
  default     = "OVERWRITE"
  description = "How to resolve field value conflicts when creating an addon that is migrating from a pre-existing self-managed installation (e.g. a metrics-server previously applied with kubectl)"

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
