variable "cluster_name" {
  type        = string
  description = "Name of the EKS cluster to install the vpc-cni addon into"

  validation {
    condition     = length(var.cluster_name) > 0
    error_message = "cluster_name must not be empty."
  }
}

variable "enable_pod_eni" {
  type        = bool
  default     = true
  description = "Whether to enable Pod ENI (branch ENI) support in the VPC CNI plugin, a prerequisite for Security Groups for Pods"
}

variable "pod_security_group_enforcing_mode" {
  type        = string
  default     = "standard"
  description = "Enforcing mode for Security Groups for Pods. 'strict' enforces only the branch ENI security groups and disables source NAT; 'standard' enforces both the primary and branch ENI security groups"

  validation {
    condition     = contains(["strict", "standard"], var.pod_security_group_enforcing_mode)
    error_message = "pod_security_group_enforcing_mode must be either 'strict' or 'standard'."
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
