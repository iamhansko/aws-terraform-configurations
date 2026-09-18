variable "namespace" {
  type        = string
  description = "Namespace the pods are created in. Must be the namespace a Fargate profile selects, or the pods stay Pending forever with no node to take them"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "create_pods" {
  type        = bool
  default     = true
  description = "Whether to create the demo pods. Off leaves the namespace, the Fargate profile and the log pipeline in place with nothing producing logs, which is both the way to stop the Fargate per-pod charge without tearing the project down and the way to watch a pod get scheduled onto Fargate by hand: apply with this false, then flip it to true and watch"
}
variable "web_pod_name" {
  type        = string
  default     = "web"
  description = "Name of the pod serving HTTP, also used as its app label value and as the name of the Service in front of it. One name rather than three variables because the _monolithic template used the same string for all three, and splitting them only creates a way for them to disagree"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.web_pod_name))
    error_message = "web_pod_name must be a valid lowercase RFC 1123 DNS label - it is used as a pod name, a Service name and a label value."
  }
}
variable "stress_pod_name" {
  type        = string
  default     = "stress"
  description = "Name of the pod generating requests, also used as its app label value"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.stress_pod_name))
    error_message = "stress_pod_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "web_image" {
  type        = string
  default     = "public.ecr.aws/docker/library/nginx:latest"
  description = "Image for the web pod. Pulled from ECR Public rather than Docker Hub, which rate-limits anonymous pulls - a Fargate pod has no local image cache, so every pod start is a fresh pull"

  validation {
    condition     = length(var.web_image) > 0
    error_message = "web_image must not be empty."
  }
}
variable "stress_image" {
  type        = string
  default     = "public.ecr.aws/eks/networking-e2e-test-images/curlimages/curl:latest"
  description = "Image for the stress pod. Needs curl and a shell, which this one has"

  validation {
    condition     = length(var.stress_image) > 0
    error_message = "stress_image must not be empty."
  }
}
variable "container_port" {
  type        = number
  default     = 80
  description = "Port the web container listens on, which the Service also publishes. 80 because that is what the nginx image serves on"

  validation {
    condition     = var.container_port > 0 && var.container_port <= 65535
    error_message = "container_port must be between 1 and 65535."
  }
}
variable "request_interval_seconds" {
  type        = number
  default     = 3
  description = "Seconds the stress pod sleeps between requests. Every request produces one nginx access log line and one status code line, so this sets how fast the demo generates records - low enough to fill a buffer quickly, high enough not to be a load test"

  validation {
    condition     = var.request_interval_seconds >= 1
    error_message = "request_interval_seconds must be at least 1. Zero would spin as fast as the network allows and turn the demo into a load generator."
  }
}
variable "restart_policy" {
  type        = string
  default     = "Always"
  description = "Container restart policy for both pods. Always, unlike the _monolithic template's 'kubectl run --restart=Never': these pods exist to emit log records continuously, and under Never a single crashed container ends the demo with a pod that looks Running in no listing and produces nothing further"

  validation {
    condition     = contains(["Always", "OnFailure", "Never"], var.restart_policy)
    error_message = "restart_policy must be one of Always, OnFailure or Never."
  }
}
