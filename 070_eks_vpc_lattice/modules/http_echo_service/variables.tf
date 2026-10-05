variable "name" {
  type        = string
  description = "Name of the Deployment, the Service and the app label both use. No default: this module is instantiated once per backend, and two instances sharing a name would fight over the same objects"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.name))
    error_message = "name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "namespace" {
  type        = string
  default     = "default"
  description = "Namespace the pair lives in, as the _monolithic template had it. Has to be the route's namespace unless the route's backendRef names this one explicitly - a backendRef that resolves to nothing leaves the route attached and answering 500"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "replicas" {
  type        = number
  default     = 2
  description = "How many pods to run, two as the _monolithic template had it. Two matters for what the demo shows: the VPC Lattice target group holds both pod addresses, so repeated requests come back with different pod names and the weighting between backends is visible"

  validation {
    condition     = var.replicas >= 1
    error_message = "replicas must be at least 1."
  }
}
variable "image" {
  type        = string
  default     = "public.ecr.aws/x2j8p8w7/http-server:latest"
  description = "Container image, as the _monolithic template had it - AWS's own sample HTTP server, which answers with the value of the PodName environment variable so responses can be told apart. On ECR Public rather than Docker Hub, which is why the floating latest tag is less of a problem here; it is still a floating tag, and there is no versioned alternative published"

  validation {
    condition     = can(regex(":[a-zA-Z0-9._-]+$|@sha256:[0-9a-f]{64}$", var.image))
    error_message = "image must carry an explicit tag or a digest."
  }
}
variable "pod_name_label" {
  type        = string
  default     = null
  description = "Text the server puts in its responses, through the PodName environment variable. Null derives it from the name as \"<name> handler pod\", which is what the _monolithic template wrote for each - deriving it means the label in the response cannot name a different service than the one answering"

  validation {
    condition     = var.pod_name_label == null || length(var.pod_name_label) > 0
    error_message = "pod_name_label must be a non-empty string, or null to derive it from the name."
  }
}
variable "service_port" {
  type        = number
  default     = 80
  description = "Port the Service publishes, which is the port an HTTPRoute's backendRef names"

  validation {
    condition     = var.service_port > 0 && var.service_port <= 65535
    error_message = "service_port must be a valid TCP port."
  }
}
variable "container_port" {
  type        = number
  default     = 8090
  description = "Port the sample server listens on. Distinct from the Service port, and it matters here: the VPC Lattice target group is built from the Service's target port, so the controller registers pods on this port rather than on the Service's"

  validation {
    condition     = var.container_port > 0 && var.container_port <= 65535
    error_message = "container_port must be a valid TCP port."
  }
}
