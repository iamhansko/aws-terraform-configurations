variable "member_cluster_names" {
  type        = list(string)
  description = "Member clusters the Deployment's replicas are divided between. Supplied from the agent modules' outputs rather than restated, because a clusterName here that matches no Cluster object is not an error - the policy is accepted and schedules nothing, and the Deployment simply reports no replicas (rules.md B-5)"

  validation {
    condition     = length(var.member_cluster_names) >= 2
    error_message = "member_cluster_names must name at least two clusters. The point of this workload is that its replicas are divided across clusters, and with one there is nothing to divide - which is the same constraint the guidance script enforced by only deploying the demo when at least two members existed."
  }
  validation {
    condition     = alltrue([for name in var.member_cluster_names : can(regex("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$", name))])
    error_message = "member_cluster_names must each be a valid lowercase RFC 1123 subdomain."
  }
}
variable "namespace" {
  type        = string
  default     = "default"
  description = "Namespace both objects are created in on the Karmada API server, as the installer created them. They have to share one: a PropagationPolicy only governs resources in its own namespace"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a valid lowercase RFC 1123 label."
  }
}
variable "propagation_policy_name" {
  type        = string
  default     = "sample-propagation"
  description = "Name of the PropagationPolicy, as the installer named it"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$", var.propagation_policy_name))
    error_message = "propagation_policy_name must be a valid lowercase RFC 1123 subdomain."
  }
}
variable "deployment_name" {
  type        = string
  default     = "karmada-demo-nginx"
  description = "Name of the Deployment, as the installer named it. Also the policy's resource selector and the app label, so one value names all three"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$", var.deployment_name))
    error_message = "deployment_name must be a valid lowercase RFC 1123 subdomain."
  }
}
variable "replicas" {
  type        = number
  default     = 4
  description = "Replicas the Deployment asks for, four as the installer's `kubectl create deployment --replicas=4` did. Divided between the member clusters rather than run in each, so with two clusters and equal weights this is two pods per cluster - a number that divides evenly by the cluster count makes that visible at a glance"

  validation {
    condition     = var.replicas >= 1
    error_message = "replicas must be at least one."
  }
}
variable "cluster_weight" {
  type        = number
  default     = 1
  description = "Weight given to the cluster group in the policy's static weight list. One, as the installer's policy had it. With a single entry covering every cluster, the value only matters relative to other entries - and there are none, so this is equal shares"

  validation {
    condition     = var.cluster_weight >= 1
    error_message = "cluster_weight must be at least one."
  }
}
variable "image_repository" {
  type        = string
  default     = "nginx"
  description = "Image the demo pods run, as the installer's `--image nginx` did"

  validation {
    condition     = length(var.image_repository) > 0
    error_message = "image_repository must not be empty."
  }
}
variable "image_tag" {
  type        = string
  default     = "1.29"
  description = "Tag for that image. Pinned, where the installer passed a bare `nginx` and therefore :latest - which in a project whose whole output is a pod count is not worth the risk of a tag moving under it"

  validation {
    condition     = length(var.image_tag) > 0
    error_message = "image_tag must not be empty."
  }
}
variable "container_name" {
  type        = string
  default     = "nginx"
  description = "Container name inside the pod template. nginx, which is what kubectl create deployment derives from the image"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.container_name))
    error_message = "container_name must be a valid lowercase RFC 1123 label."
  }
}
variable "container_port" {
  type        = number
  default     = 80
  description = "Port declared on the container. Declarative only - nothing connects to these pods, and no Service is created, because the installer created none either"

  validation {
    condition     = var.container_port > 0 && var.container_port <= 65535
    error_message = "container_port must be between 1 and 65535."
  }
}
