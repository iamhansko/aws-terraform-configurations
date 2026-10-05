variable "name" {
  type        = string
  default     = "nginx"
  description = "Name of the Deployment and the value of its app label"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.name))
    error_message = "name must be a valid lowercase RFC 1123 label."
  }
}

variable "namespace" {
  type        = string
  default     = "default"
  description = "Namespace the Deployment is created in"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a valid lowercase RFC 1123 label."
  }
}

variable "image" {
  type        = string
  default     = "public.ecr.aws/nginx/nginx:1.29"
  description = "Image the pods run, tagged. The _monolithic template used a bare \"nginx\", which is Docker Hub's latest - unpinned, and subject to Docker Hub's anonymous pull rate limit from a NAT gateway address every node in the VPC shares"

  validation {
    condition     = can(regex(":", var.image))
    error_message = "image must carry an explicit tag; an untagged reference resolves to latest and changes under you."
  }
}

variable "replicas" {
  type        = number
  default     = 10
  description = "Replica count, as the _monolithic template set it. Ten is the number that makes the node's pod ceiling visible: with one node there is a point where the next pod stays Pending, and that point is what this variant demonstrates"

  validation {
    condition     = var.replicas >= 1
    error_message = "replicas must be at least 1."
  }
}

variable "container_port" {
  type        = number
  default     = 80
  description = "Port the container listens on. Declared for readability; nothing routes to it in this project"

  validation {
    condition     = var.container_port > 0 && var.container_port <= 65535
    error_message = "container_port must be a valid TCP port."
  }
}

variable "cpu_request" {
  type        = string
  default     = "10m"
  description = "CPU request per pod. Deliberately tiny, so what limits the replica count is the pod ceiling rather than the CPU - which is the thing being demonstrated"

  validation {
    condition     = can(regex("^[0-9]+m?$", var.cpu_request))
    error_message = "cpu_request must be a Kubernetes CPU quantity such as 10m or 1."
  }
}

variable "memory_request" {
  type        = string
  default     = "16Mi"
  description = "Memory request per pod"

  validation {
    condition     = can(regex("^[0-9]+(Ki|Mi|Gi)$", var.memory_request))
    error_message = "memory_request must be a Kubernetes memory quantity such as 16Mi."
  }
}

variable "memory_limit" {
  type        = string
  default     = "64Mi"
  description = "Memory limit per pod. Exceeding it kills the container, which is a failure worth having - unlike a CPU limit, which only throttles"

  validation {
    condition     = can(regex("^[0-9]+(Ki|Mi|Gi)$", var.memory_limit))
    error_message = "memory_limit must be a Kubernetes memory quantity such as 64Mi."
  }
}
