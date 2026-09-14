variable "name" {
  type        = string
  description = "Name of the EKS cluster"

  validation {
    condition     = length(var.name) > 0
    error_message = "name must not be empty."
  }
}

variable "kubernetes_version" {
  type        = string
  default     = "1.36"
  description = "EKS cluster Kubernetes version (1.XX)"

  validation {
    condition     = contains(["1.34", "1.35", "1.36"], var.kubernetes_version)
    error_message = "kubernetes_version must be one of: 1.34, 1.35, 1.36."
  }
}

variable "subnet_ids" {
  type        = list(string)
  description = "Subnet IDs attached to the EKS cluster's VPC configuration"

  validation {
    condition     = length(var.subnet_ids) > 0
    error_message = "subnet_ids must contain at least one subnet ID."
  }
}

variable "endpoint_private_access" {
  type        = bool
  default     = true
  description = "Whether the EKS cluster API server endpoint is reachable from within the VPC"
}

variable "endpoint_public_access" {
  type        = bool
  default     = true
  description = "Whether the EKS cluster API server endpoint is reachable from the public internet"
}

variable "enabled_cluster_log_types" {
  type        = list(string)
  default     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  description = "EKS control plane log types to enable in CloudWatch Logs"
}
