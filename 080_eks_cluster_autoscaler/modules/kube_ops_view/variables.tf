variable "name" {
  type        = string
  default     = "kube-ops-view"
  description = "Name shared by the Deployment, Service and ServiceAccount"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.name))
    error_message = "name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "namespace" {
  type        = string
  default     = "kube-system"
  description = "Namespace the dashboard is created in"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "cluster_role_name" {
  type        = string
  default     = "kube-ops-view"
  description = "Name of the ClusterRole and ClusterRoleBinding. Cluster-scoped, so it must not collide with another install of this dashboard in the same cluster"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$", var.cluster_role_name))
    error_message = "cluster_role_name must be a valid lowercase RFC 1123 name."
  }
}
variable "image_repository" {
  type        = string
  default     = "docker.io/hjacobs/kube-ops-view"
  description = "Container image repository. This is where the upstream author publishes the image; the project is in maintenance mode, so the tag rarely moves"

  validation {
    condition     = length(var.image_repository) > 0
    error_message = "image_repository must not be empty."
  }
}
variable "image_tag" {
  type        = string
  default     = "23.5.0"
  description = "Container image tag. 23.5.0 is the last upstream release and the version the community Helm chart pins"

  validation {
    condition     = length(var.image_tag) > 0
    error_message = "image_tag must not be empty."
  }
}
variable "image_pull_policy" {
  type        = string
  default     = "IfNotPresent"
  description = "Image pull policy. IfNotPresent rather than the chart's Always, since image_tag is a fixed release rather than a moving tag"

  validation {
    condition     = contains(["Always", "IfNotPresent", "Never"], var.image_pull_policy)
    error_message = "image_pull_policy must be one of: Always, IfNotPresent, Never."
  }
}
variable "replica_count" {
  type        = number
  default     = 1
  description = "Number of dashboard replicas. One is the sensible default: sharing UI state across replicas is what the chart's optional Redis dependency exists for, and a read-only dashboard does not need the availability"

  validation {
    condition     = var.replica_count > 0
    error_message = "replica_count must be greater than zero."
  }
}
variable "container_port" {
  type        = number
  default     = 8080
  description = "Port the container listens on. Fixed by the application"

  validation {
    condition     = var.container_port > 0 && var.container_port <= 65535
    error_message = "container_port must be a valid TCP port."
  }
}
variable "service_port" {
  type        = number
  default     = 80
  description = "Port the Service exposes"

  validation {
    condition     = var.service_port > 0 && var.service_port <= 65535
    error_message = "service_port must be a valid TCP port."
  }
}
variable "service_type" {
  type        = string
  default     = "ClusterIP"
  description = "Service type. ClusterIP keeps the dashboard private (reach it with 'kubectl port-forward'); LoadBalancer publishes it, which for a dashboard with no authentication means anyone who can reach the load balancer sees the cluster's nodes and pods"

  validation {
    condition     = contains(["ClusterIP", "NodePort", "LoadBalancer"], var.service_type)
    error_message = "service_type must be one of: ClusterIP, NodePort, LoadBalancer."
  }
}
variable "service_annotations" {
  type        = map(string)
  default     = {}
  description = "Annotations set on the Service. With service_type = LoadBalancer these drive the AWS Load Balancer Controller: aws-load-balancer-type = external moves off the in-tree Classic Load Balancer path, and aws-load-balancer-scheme / -nlb-target-type / -security-groups shape the NLB. This is the declarative form of the 'kubectl patch svc kube-ops-view -p ...' step in the _monolithic userdata"

  validation {
    condition     = alltrue([for key in keys(var.service_annotations) : length(key) > 0])
    error_message = "service_annotations must not contain empty annotation keys."
  }
}
variable "cpu_request" {
  type        = string
  default     = "50m"
  description = "CPU request per replica"

  validation {
    condition     = can(regex("^([0-9]+m|[0-9]+(\\.[0-9]+)?)$", var.cpu_request))
    error_message = "cpu_request must be a Kubernetes CPU quantity (e.g. 50m)."
  }
}
variable "cpu_limit" {
  type        = string
  default     = "200m"
  description = "CPU limit per replica"

  validation {
    condition     = can(regex("^([0-9]+m|[0-9]+(\\.[0-9]+)?)$", var.cpu_limit))
    error_message = "cpu_limit must be a Kubernetes CPU quantity (e.g. 200m)."
  }
}
variable "memory_request" {
  type        = string
  default     = "64Mi"
  description = "Memory request per replica"

  validation {
    condition     = can(regex("^[0-9]+(Ei|Pi|Ti|Gi|Mi|Ki)$", var.memory_request))
    error_message = "memory_request must be a Kubernetes binary quantity (e.g. 64Mi)."
  }
}
variable "memory_limit" {
  type        = string
  default     = "256Mi"
  description = "Memory limit per replica"

  validation {
    condition     = can(regex("^[0-9]+(Ei|Pi|Ti|Gi|Mi|Ki)$", var.memory_limit))
    error_message = "memory_limit must be a Kubernetes binary quantity (e.g. 256Mi)."
  }
}
