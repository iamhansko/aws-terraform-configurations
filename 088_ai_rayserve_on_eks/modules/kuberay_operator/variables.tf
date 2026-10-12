variable "release_name" {
  type        = string
  default     = "kuberay-operator"
  description = "Helm release name"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.release_name))
    error_message = "release_name must be a valid lowercase RFC 1123 label."
  }
}

variable "namespace" {
  type        = string
  default     = "kuberay-operator"
  description = "Namespace the operator runs in, as the _monolithic template placed it"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a valid lowercase RFC 1123 label."
  }
}

variable "create_namespace" {
  type        = bool
  default     = true
  description = "Whether Helm creates the namespace. True, so the namespace belongs to the release and is removed with it - the _monolithic template created it with kubectl beforehand, which left it behind on uninstall"
}

variable "chart_repository" {
  type        = string
  default     = "https://ray-project.github.io/kuberay-helm"
  description = "Helm repository the KubeRay chart comes from"

  validation {
    condition     = can(regex("^https://", var.chart_repository))
    error_message = "chart_repository must be an https URL."
  }
}

variable "chart_version" {
  type        = string
  default     = "1.4.2"
  description = "Pinned kuberay-operator chart version, as the _monolithic template pinned it. The operator version also decides which RayService API version is served, so this is not a value to leave floating"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.chart_version))
    error_message = "chart_version must be a three-part semantic version."
  }
}

variable "replica_count" {
  type        = number
  default     = 1
  description = "Number of operator replicas. One is enough: the operator leader-elects, so a second replica is standby rather than capacity"

  validation {
    condition     = var.replica_count >= 1
    error_message = "replica_count must be at least 1."
  }
}

variable "cpu_request" {
  type        = string
  default     = "100m"
  description = "CPU request for the operator pod"

  validation {
    condition     = can(regex("^[0-9]+m?$", var.cpu_request))
    error_message = "cpu_request must be a Kubernetes CPU quantity such as 100m or 1."
  }
}

variable "memory_request" {
  type        = string
  default     = "512Mi"
  description = "Memory request for the operator pod"

  validation {
    condition     = can(regex("^[0-9]+(Ki|Mi|Gi)$", var.memory_request))
    error_message = "memory_request must be a Kubernetes memory quantity such as 512Mi."
  }
}

variable "timeout_seconds" {
  type        = number
  default     = 600
  description = "How long the apply waits for the operator Deployment to become Available"

  validation {
    condition     = var.timeout_seconds >= 120
    error_message = "timeout_seconds must be at least 120."
  }
}

variable "additional_set_values" {
  type = list(object({
    name  = string
    value = string
    type  = optional(string)
  }))
  default     = []
  description = "Extra chart values, for narrowing the operator's watched namespaces or adding tolerations without editing the module"

  validation {
    condition     = alltrue([for entry in var.additional_set_values : entry.type == null || contains(["auto", "string"], entry.type)])
    error_message = "additional_set_values entries may only set type to \"auto\" or \"string\"; those are the two helm --set accepts (rules.md E-7)."
  }
}
