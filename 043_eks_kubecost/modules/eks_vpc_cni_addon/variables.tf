variable "cluster_name" {
  type        = string
  description = "Name of the EKS cluster to install the vpc-cni addon into"

  validation {
    condition     = length(var.cluster_name) > 0
    error_message = "cluster_name must not be empty."
  }
}
variable "addon_version" {
  type        = string
  default     = null
  description = "Specific vpc-cni addon version (e.g. v1.20.0-eksbuild.1). When null, EKS picks the default version for the cluster's Kubernetes version"

  validation {
    condition     = var.addon_version == null || can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+-eksbuild\\.[0-9]+$", var.addon_version))
    error_message = "addon_version must look like v1.20.0-eksbuild.1, or null."
  }
}
variable "env" {
  type        = map(string)
  default     = {}
  description = "Environment variables set on the aws-node DaemonSet (e.g. ENABLE_PREFIX_DELEGATION, ENABLE_POD_ENI). Rendered into the addon's configuration_values instead of running 'kubectl set env daemonset aws-node' from a shell. When empty, configuration_values is left unset so EKS applies the addon defaults"

  validation {
    condition     = alltrue([for key in keys(var.env) : length(key) > 0])
    error_message = "env must not contain empty environment variable names."
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
