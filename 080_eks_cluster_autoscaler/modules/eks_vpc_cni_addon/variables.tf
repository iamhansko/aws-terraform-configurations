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
variable "enable_network_policy" {
  type        = bool
  default     = null
  description = "Whether the VPC CNI enforces Kubernetes NetworkPolicy objects itself, through the network policy agent the addon runs alongside aws-node. Null leaves the key out of configuration_values entirely, so EKS applies its own default (off). This is a top-level key in the addon's configuration schema rather than a DaemonSet environment variable, so it does not belong in var.env - a value placed there renders under env and is silently ignored (rules.md E-5). Without it the API server accepts NetworkPolicy objects and nothing enforces them, which looks like a policy that does not work rather than a feature that was never switched on"
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
