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

variable "compute_type" {
  type        = string
  default     = "Fargate"
  description = "Where the CoreDNS pods run. 'Fargate' drops the eks.amazonaws.com/compute-type: ec2 annotation EKS ships the Deployment with, without which the pods stay Pending on a cluster that has no EC2 nodes. 'ec2' is the value for a cluster with a node group"

  validation {
    condition     = contains(["Fargate", "ec2"], var.compute_type)
    error_message = "compute_type must be either Fargate or ec2 - the two values the coredns addon's computeType configuration accepts."
  }
}
