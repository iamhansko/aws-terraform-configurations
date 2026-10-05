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
  description = "Specific metrics-server addon version (e.g. v0.9.0-eksbuild.11). When null, EKS picks the default version for the cluster's Kubernetes version - which is what this project does, so the version follows the cluster rather than having to be raised alongside it"

  validation {
    condition     = var.addon_version == null || can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+-eksbuild\\.[0-9]+$", var.addon_version))
    error_message = "addon_version must look like v0.9.0-eksbuild.11, or null."
  }
}
variable "resolve_conflicts_on_create" {
  type        = string
  default     = "OVERWRITE"
  description = "How to resolve field value conflicts when creating an addon that is migrating from a pre-existing self-managed installation. OVERWRITE matters for this addon in particular: metrics-server is commonly installed from its upstream Helm chart or a plain manifest first, and NONE would then fail the creation on the objects that already exist (rules.md C-4)"

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
variable "replicas" {
  type        = number
  default     = 2
  description = "Number of metrics-server replicas, which is also the addon's own default. Two is safe on a single-node cluster because the addon's pod anti-affinity is preferred rather than required - both pods schedule onto the one node. Set it to one to stop paying for the second on a cluster that has only one node anyway"

  validation {
    condition     = var.replicas >= 1
    error_message = "replicas must be at least 1 - a metrics-server deployment scaled to zero leaves every HorizontalPodAutoscaler reporting unknown metrics, which does not look like a missing addon."
  }
}
