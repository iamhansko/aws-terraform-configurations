variable "name" {
  type        = string
  default     = "hamster"
  description = "Name of the Deployment. The VerticalPodAutoscaler is named <name>-vpa and targets it, following the upstream example this is a translation of"
  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.name))
    error_message = "name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "namespace" {
  type        = string
  default     = "default"
  description = "Namespace the workload is created in"
  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "image" {
  type        = string
  default     = "registry.k8s.io/ubuntu-slim:0.14"
  description = "Container image, as the upstream hamster example uses it. The image barely matters - the container is a shell loop that burns CPU in bursts, which is what gives the recommender something to measure"
  validation {
    condition     = length(var.image) > 0
    error_message = "image must not be empty."
  }
}
variable "replicas" {
  type        = number
  default     = 2
  description = "Replica count, two as the upstream example has it. Two matters for the demo: the updater will not evict every pod of a workload at once, so with a single replica an Auto-mode VPA has nothing it is allowed to disrupt and the recommendation never gets applied"
  validation {
    condition     = var.replicas >= 1
    error_message = "replicas must be at least 1."
  }
}
variable "cpu_request" {
  type        = string
  default     = "100m"
  description = "Initial CPU request, deliberately lower than what the container actually uses. The gap between this and observed usage is the recommendation, and closing it is what the demo shows"
  validation {
    condition     = can(regex("^[0-9]+(m|\\.[0-9]+)?$", var.cpu_request))
    error_message = "cpu_request must be a Kubernetes CPU quantity, e.g. 100m."
  }
}
variable "memory_request" {
  type        = string
  default     = "50Mi"
  description = "Initial memory request"
  validation {
    condition     = can(regex("^[0-9]+(Mi|Gi|M|G)$", var.memory_request))
    error_message = "memory_request must be a Kubernetes memory quantity, e.g. 50Mi."
  }
}
variable "min_allowed_cpu" {
  type        = string
  default     = "100m"
  description = "Floor the VPA may recommend for CPU. A floor is not cosmetic: without one the recommender can drive an idle container's request low enough that it cannot start again promptly"
  validation {
    condition     = can(regex("^[0-9]+(m|\\.[0-9]+)?$", var.min_allowed_cpu))
    error_message = "min_allowed_cpu must be a Kubernetes CPU quantity, e.g. 100m."
  }
}
variable "min_allowed_memory" {
  type        = string
  default     = "50Mi"
  description = "Floor the VPA may recommend for memory"
  validation {
    condition     = can(regex("^[0-9]+(Mi|Gi|M|G)$", var.min_allowed_memory))
    error_message = "min_allowed_memory must be a Kubernetes memory quantity, e.g. 50Mi."
  }
}
variable "max_allowed_cpu" {
  type        = string
  default     = "1"
  description = "Ceiling the VPA may recommend for CPU. Also what stops a recommendation from exceeding what a node can allocate, which would leave the rewritten pod permanently Pending"
  validation {
    condition     = can(regex("^[0-9]+(m|\\.[0-9]+)?$", var.max_allowed_cpu))
    error_message = "max_allowed_cpu must be a Kubernetes CPU quantity, e.g. 1 or 1000m."
  }
}
variable "max_allowed_memory" {
  type        = string
  default     = "500Mi"
  description = "Ceiling the VPA may recommend for memory"
  validation {
    condition     = can(regex("^[0-9]+(Mi|Gi|M|G)$", var.max_allowed_memory))
    error_message = "max_allowed_memory must be a Kubernetes memory quantity, e.g. 500Mi."
  }
}
variable "update_mode" {
  type        = string
  default     = "Auto"
  description = "What the VPA is allowed to do with its recommendation. Off only records it, Initial applies it to new pods, Recreate and Auto also evict running pods whose requests are far off - so Auto is the only mode where the demo visibly changes a running workload"
  validation {
    condition     = contains(["Off", "Initial", "Recreate", "Auto"], var.update_mode)
    error_message = "update_mode must be one of Off, Initial, Recreate or Auto."
  }
}
variable "controlled_resources" {
  type        = list(string)
  default     = ["cpu", "memory"]
  description = "Which resources the VPA manages"
  validation {
    condition     = length(var.controlled_resources) > 0 && alltrue([for resource in var.controlled_resources : contains(["cpu", "memory"], resource)])
    error_message = "controlled_resources must be a non-empty list containing only cpu and memory."
  }
}
variable "run_as_user" {
  type        = number
  default     = 65534
  description = "UID the container runs as, 65534 (nobody) as the upstream example sets it alongside runAsNonRoot"
  validation {
    condition     = var.run_as_user > 0
    error_message = "run_as_user must be positive; 0 would be root, which runAsNonRoot rejects."
  }
}
