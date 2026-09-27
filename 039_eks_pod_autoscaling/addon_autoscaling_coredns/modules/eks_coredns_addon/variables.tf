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
  default     = 2
  description = "Number of CoreDNS replicas"

  validation {
    condition     = var.coredns_replica_count > 0
    error_message = "coredns_replica_count must be greater than zero."
  }
}
variable "autoscaling_enabled" {
  type        = bool
  default     = false
  description = "Whether the addon manages CoreDNS replica count itself. EKS supports this natively from addon versions built for Kubernetes 1.29 onwards, which is what makes a separate cluster-proportional-autoscaler Helm release unnecessary. When true, coredns_replica_count is not sent at all - the two settings are alternatives and a fixed count would just be overwritten"
}
variable "autoscaling_min_replicas" {
  type        = number
  default     = 2
  description = "Floor for the addon's own autoscaler. Two rather than one so DNS survives a single node going away, which is the same reason coredns_replica_count defaults to two"

  validation {
    condition     = var.autoscaling_min_replicas >= 1
    error_message = "autoscaling_min_replicas must be at least 1."
  }
}
variable "autoscaling_max_replicas" {
  type        = number
  default     = 4
  description = "Ceiling for the addon's own autoscaler. The addon scales CoreDNS with the size of the cluster, so this is what stops a large node count from turning into a large number of DNS pods"

  validation {
    condition     = var.autoscaling_max_replicas >= 1
    error_message = "autoscaling_max_replicas must be at least 1."
  }
  validation {
    # A pair constraint rather than a property of either value, which is what a
    # cross-variable condition is for (rules.md B-1). EKS accepts max < min and the
    # addon then never leaves DEGRADED, with the reason only in its status.
    condition     = var.autoscaling_max_replicas >= var.autoscaling_min_replicas
    error_message = "autoscaling_max_replicas must be greater than or equal to autoscaling_min_replicas."
  }
}
