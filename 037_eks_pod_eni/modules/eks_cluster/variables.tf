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
  default     = "1.33"
  description = "EKS cluster Kubernetes version (1.XX)"

  validation {
    condition     = contains(["1.31", "1.32", "1.33"], var.kubernetes_version)
    error_message = "kubernetes_version must be one of: 1.31, 1.32, 1.33."
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
  default     = false
  description = "Whether the EKS cluster API server endpoint is reachable from the public internet"
}

variable "public_access_cidrs" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = "CIDR blocks allowed to reach the EKS API server's public endpoint when endpoint_public_access is true. Ignored when endpoint_public_access is false"

  validation {
    condition     = alltrue([for cidr in var.public_access_cidrs : can(cidrhost(cidr, 0))])
    error_message = "public_access_cidrs must contain valid IPv4 CIDR blocks."
  }
}

variable "enabled_cluster_log_types" {
  type        = list(string)
  default     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  description = "EKS control plane log types to enable in CloudWatch Logs"
}

variable "cluster_iam_policy_arns" {
  type = list(string)
  default = [
    "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy",
    "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController",
  ]
  description = "IAM managed policy ARNs attached to the EKS cluster's IAM role"

  validation {
    condition     = alltrue([for arn in var.cluster_iam_policy_arns : can(regex("^arn:aws:iam::", arn))])
    error_message = "cluster_iam_policy_arns must contain valid IAM policy ARNs."
  }
}
