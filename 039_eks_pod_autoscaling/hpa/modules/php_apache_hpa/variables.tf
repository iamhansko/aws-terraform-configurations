variable "name" {
  type        = string
  default     = "php-apache"
  description = "Name shared by the Deployment, the Service and the HorizontalPodAutoscaler. The Service name is also the hostname the load generator requests, so changing it changes the command in the outputs"
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
  default     = "registry.k8s.io/hpa-example"
  description = "Container image. registry.k8s.io, not the us.gcr.io/k8s-artifacts-prod path the _monolithic template used: that registry was the old staging mirror and is deprecated, so the pull is one retirement away from failing. The image is the same upstream hpa-example - a PHP page that burns CPU on every request, which is what makes a CPU-target HPA demonstrable at all"
  validation {
    condition     = length(var.image) > 0
    error_message = "image must not be empty."
  }
}
variable "replicas" {
  type        = number
  default     = 1
  description = "Initial replica count. One, matching the autoscaler's floor, so the first thing the HPA does is nothing - the demo starts from the bottom of the range"
  validation {
    condition     = var.replicas >= 1
    error_message = "replicas must be at least 1."
  }
}
variable "container_port" {
  type        = number
  default     = 80
  description = "Port the container and the Service listen on"
  validation {
    condition     = var.container_port > 0 && var.container_port <= 65535
    error_message = "container_port must be between 1 and 65535."
  }
}
variable "cpu_request" {
  type        = string
  default     = "200m"
  description = "CPU request on the container. Not optional decoration: a CPU-target HPA computes utilisation as usage divided by the request, so without a request there is nothing to divide by and the HPA reports <unknown> targets and never scales. The _monolithic template set this in a separate 'kubectl set resources' call for the same reason"
  validation {
    condition     = can(regex("^[0-9]+(m|\\.[0-9]+)?$", var.cpu_request))
    error_message = "cpu_request must be a Kubernetes CPU quantity, e.g. 200m or 0.5."
  }
}
variable "cpu_limit" {
  type        = string
  default     = null
  description = "Optional CPU limit on the container, or null for none. Null by default, as the _monolithic template had it: a limit caps the utilisation the HPA can observe, so the demo reaches its target faster without one (rules.md B-4)"
  validation {
    condition     = var.cpu_limit == null || can(regex("^[0-9]+(m|\\.[0-9]+)?$", var.cpu_limit))
    error_message = "cpu_limit must be a Kubernetes CPU quantity, e.g. 500m, or null."
  }
}
variable "target_cpu_utilization_percentage" {
  type        = number
  default     = 60
  description = "Average CPU utilisation, as a percentage of the request, the HPA aims to hold. 60 as the _monolithic template's 'kubectl autoscale --cpu-percent=60' set it"
  validation {
    condition     = var.target_cpu_utilization_percentage > 0 && var.target_cpu_utilization_percentage <= 100
    error_message = "target_cpu_utilization_percentage must be between 1 and 100."
  }
}
variable "min_replicas" {
  type        = number
  default     = 1
  description = "Floor for the HPA"
  validation {
    condition     = var.min_replicas >= 1
    error_message = "min_replicas must be at least 1."
  }
}
variable "max_replicas" {
  type        = number
  default     = 15
  description = "Ceiling for the HPA, 15 as the _monolithic template set it. Deliberately more replicas than the node group can hold at its minimum size, so the demo also shows pods going Pending - which is what makes the node-side half of autoscaling visible"
  validation {
    condition     = var.max_replicas >= 1
    error_message = "max_replicas must be at least 1."
  }
  validation {
    condition     = var.max_replicas >= var.min_replicas
    error_message = "max_replicas must be greater than or equal to min_replicas."
  }
}
