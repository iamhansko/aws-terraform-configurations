variable "cluster_name" {
  type        = string
  description = "Name of the EKS cluster this Fargate profile belongs to"

  validation {
    condition     = length(var.cluster_name) > 0
    error_message = "cluster_name must not be empty."
  }
}

variable "profile_name" {
  type        = string
  description = "Name of the EKS Fargate profile"

  validation {
    condition     = length(var.profile_name) > 0
    error_message = "profile_name must not be empty."
  }
}

variable "subnet_ids" {
  type        = list(string)
  description = "Private subnet IDs used by Fargate pods"

  validation {
    condition     = length(var.subnet_ids) > 0
    error_message = "subnet_ids must contain at least one subnet ID."
  }
}

variable "namespace" {
  type        = string
  default     = "kube-system"
  description = "Kubernetes namespace selected by this Fargate profile"

  validation {
    condition     = length(var.namespace) > 0
    error_message = "namespace must not be empty."
  }
}

variable "reschedule_deployment_name" {
  type        = string
  default     = null
  description = "Optional name of a Deployment in var.namespace (e.g. 'coredns') to reschedule onto Fargate after this profile is created. Existing pods are not matched by a Fargate profile retroactively, so a rollout must be triggered. When null, no rollout is triggered."
}
