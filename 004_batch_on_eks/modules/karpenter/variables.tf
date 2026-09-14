variable "cluster_name" {
  type        = string
  description = "Name of the EKS cluster Karpenter provisions nodes for"

  validation {
    condition     = length(var.cluster_name) > 0
    error_message = "cluster_name must not be empty."
  }
}

variable "oidc_provider_arn" {
  type        = string
  description = "ARN of the cluster's IAM OIDC provider (used for the controller's IRSA trust policy)"

  validation {
    condition     = can(regex("^arn:aws:iam::", var.oidc_provider_arn))
    error_message = "oidc_provider_arn must be a valid IAM OIDC provider ARN."
  }
}

variable "oidc_issuer_host" {
  type        = string
  description = "Cluster OIDC issuer URL without the https:// scheme, used in the trust policy's sub/aud condition keys"

  validation {
    condition     = length(var.oidc_issuer_host) > 0
    error_message = "oidc_issuer_host must not be empty."
  }
}

variable "namespace" {
  type        = string
  default     = "kube-system"
  description = "Kubernetes namespace Karpenter (controller and service account) is installed into"

  validation {
    condition     = length(var.namespace) > 0
    error_message = "namespace must not be empty."
  }
}

variable "service_account_name" {
  type        = string
  default     = "karpenter"
  description = "Kubernetes service account name used by the Karpenter controller"

  validation {
    condition     = length(var.service_account_name) > 0
    error_message = "service_account_name must not be empty."
  }
}

variable "controller_policy_arns" {
  type        = list(string)
  default     = ["arn:aws:iam::aws:policy/AdministratorAccess"]
  description = "IAM managed policy ARNs attached to the Karpenter controller's IAM role"

  validation {
    condition     = alltrue([for arn in var.controller_policy_arns : can(regex("^arn:aws:iam::", arn))])
    error_message = "controller_policy_arns must contain valid IAM policy ARNs."
  }
}

variable "node_iam_policy_arns" {
  type = list(string)
  default = [
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
  ]
  description = "IAM managed policy ARNs attached to the Karpenter-managed node IAM role"

  validation {
    condition     = alltrue([for arn in var.node_iam_policy_arns : can(regex("^arn:aws:iam::", arn))])
    error_message = "node_iam_policy_arns must contain valid IAM policy ARNs."
  }
}


variable "chart_version" {
  type        = string
  default     = "1.14.0"
  description = "Version of the Karpenter Helm chart to install"

  validation {
    condition     = length(var.chart_version) > 0
    error_message = "chart_version must not be empty."
  }
}

variable "controller_cpu_request" {
  type        = string
  default     = "1"
  description = "CPU request for the Karpenter controller pod"
}

variable "controller_memory_request" {
  type        = string
  default     = "1Gi"
  description = "Memory request for the Karpenter controller pod"
}

variable "controller_cpu_limit" {
  type        = string
  default     = "1"
  description = "CPU limit for the Karpenter controller pod"
}

variable "controller_memory_limit" {
  type        = string
  default     = "1Gi"
  description = "Memory limit for the Karpenter controller pod"
}
