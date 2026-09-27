variable "cluster_name" {
  type        = string
  description = "Name of the EKS cluster to install the coredns addon into"

  validation {
    condition     = length(var.cluster_name) > 0
    error_message = "cluster_name must not be empty."
  }
}

variable "addon_version" {
  type        = string
  default     = null
  description = "Specific coredns addon version (e.g. v1.12.1-eksbuild.2). When null, EKS picks the default version for the cluster's Kubernetes version"

  validation {
    condition     = var.addon_version == null || can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+-eksbuild\\.[0-9]+$", var.addon_version))
    error_message = "addon_version must look like v1.12.1-eksbuild.2, or null."
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

variable "coredns_replica_count" {
  type        = number
  default     = null
  description = "Number of CoreDNS replicas, or null to send no configuration_values at all and leave the addon on its own default. Null is what this variant wants: the cluster-proportional-autoscaler owns this Deployment's replica count at runtime, and a replicaCount held in the addon's configuration is a second opinion about the same number - EKS reasserts it on every addon update, undoing the autoscaler until it next reconciles (rules.md B-4)"

  validation {
    condition     = var.coredns_replica_count == null || var.coredns_replica_count > 0
    error_message = "coredns_replica_count must be greater than zero, or null to leave the addon on its default."
  }
}
