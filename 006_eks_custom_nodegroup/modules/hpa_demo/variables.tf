variable "name" {
  type        = string
  default     = "php-apache"
  description = "Name shared by the demo Deployment, Service and HorizontalPodAutoscaler"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.name))
    error_message = "name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "namespace" {
  type        = string
  default     = "default"
  description = "Namespace the demo workload is created in"

  validation {
    condition     = length(var.namespace) > 0
    error_message = "namespace must not be empty."
  }
}
variable "image" {
  type        = string
  default     = "registry.k8s.io/hpa-example"
  description = "Container image for the demo workload. The upstream HPA walkthrough image serves a page that burns CPU per request, which is what makes load generation move the metric. The _monolithic template used the retired us.gcr.io/k8s-artifacts-prod mirror of the same image"

  validation {
    condition     = length(var.image) > 0
    error_message = "image must not be empty."
  }
}
variable "container_port" {
  type        = number
  default     = 80
  description = "Port the demo container listens on"

  validation {
    condition     = var.container_port > 0 && var.container_port <= 65535
    error_message = "container_port must be a valid TCP port."
  }
}
variable "service_port" {
  type        = number
  default     = 80
  description = "Port the demo Service exposes"

  validation {
    condition     = var.service_port > 0 && var.service_port <= 65535
    error_message = "service_port must be a valid TCP port."
  }
}
variable "cpu_request" {
  type        = string
  default     = "200m"
  description = "CPU request per replica. The HPA computes utilization as a percentage of this request, so without it target_cpu_utilization_percentage has no denominator and the autoscaler reports <unknown>"

  validation {
    condition     = can(regex("^([0-9]+m|[0-9]+(\\.[0-9]+)?)$", var.cpu_request))
    error_message = "cpu_request must be a Kubernetes CPU quantity (e.g. 200m or 0.5)."
  }
}
variable "cpu_limit" {
  type        = string
  default     = "500m"
  description = "CPU limit per replica, capping how much one pod can absorb so load actually spreads to new replicas"

  validation {
    condition     = can(regex("^([0-9]+m|[0-9]+(\\.[0-9]+)?)$", var.cpu_limit))
    error_message = "cpu_limit must be a Kubernetes CPU quantity (e.g. 500m or 1)."
  }
}
variable "target_cpu_utilization_percentage" {
  type        = number
  default     = 60
  description = "Average CPU utilization, as a percentage of cpu_request, the HorizontalPodAutoscaler steers toward"

  validation {
    condition     = var.target_cpu_utilization_percentage > 0 && var.target_cpu_utilization_percentage <= 100
    error_message = "target_cpu_utilization_percentage must be between 1 and 100."
  }
}
variable "min_replicas" {
  type        = number
  default     = 1
  description = "Minimum replica count the HorizontalPodAutoscaler scales down to"

  validation {
    condition     = var.min_replicas > 0
    error_message = "min_replicas must be greater than zero."
  }
}
variable "max_replicas" {
  type        = number
  default     = 10
  description = "Maximum replica count the HorizontalPodAutoscaler scales up to. Set high enough that scale-up exhausts the node groups and forces the cluster autoscaler to add nodes, which is the point of the demo"

  validation {
    condition     = var.max_replicas > 0
    error_message = "max_replicas must be greater than zero."
  }
}
variable "node_selector" {
  type        = map(string)
  default     = {}
  description = "nodeSelector applied to the demo pods, e.g. the app node group's labels output, so scale-up lands on the intended node group. When empty, the scheduler may place pods on any node group"

  validation {
    condition     = alltrue([for key in keys(var.node_selector) : length(key) > 0])
    error_message = "node_selector must not contain empty nodeSelector keys."
  }
}
