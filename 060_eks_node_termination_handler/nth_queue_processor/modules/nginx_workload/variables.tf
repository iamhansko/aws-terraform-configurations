variable "name" {
  type        = string
  default     = "nginx"
  description = "Name of the Deployment and the label its pods carry"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.name))
    error_message = "name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "namespace" {
  type        = string
  default     = "default"
  description = "Namespace the Deployment runs in, as the _monolithic template had it. Not created here - default already exists, and a module that created it would delete it on destroy"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "replicas" {
  type        = number
  default     = 12
  description = "How many pods to run, twelve as the _monolithic template had it. The number matters for what the demo shows: enough replicas that every node holds several, so interrupting one instance evicts a visible group rather than a single pod"

  validation {
    condition     = var.replicas >= 1
    error_message = "replicas must be at least 1."
  }
}
variable "image" {
  type        = string
  default     = "public.ecr.aws/nginx/nginx:1.29.5-alpine"
  description = "Container image. Pinned and from ECR Public, where the _monolithic template used the bare name \"nginx\" - which resolves to docker.io/library/nginx:latest: a floating tag on a registry that rate-limits anonymous pulls per source address, and every node here shares one NAT gateway address per zone. A demo that deliberately replaces nodes pulls this image again each time, which is the pattern that hits the limit"

  validation {
    condition     = can(regex(":[a-zA-Z0-9._-]+$", var.image))
    error_message = "image must carry an explicit tag."
  }
}
variable "node_selector" {
  type        = map(string)
  default     = {}
  description = "Labels a node must carry for these pods to land on it. Empty for a demo where the handler covers every node, since there is nothing to pin to. Set from a Karpenter node pool's labels when the point is to keep the pods on that pool - and take the value from the pool's output rather than restating it, because a selector matching nothing leaves every pod Pending and Karpenter will not provision for a label no pool applies (rules.md B-5)"

  validation {
    condition     = alltrue([for key in keys(var.node_selector) : length(key) > 0])
    error_message = "node_selector must not contain empty label keys."
  }
}
variable "cpu_request" {
  type        = string
  default     = "250m"
  description = "CPU request per pod. The _monolithic template set no requests at all, which lets the scheduler stack every replica onto one node - so an interruption sent to any other node drains nothing and the demo looks like a success. A real request forces the replicas to spread"

  validation {
    condition     = can(regex("^[0-9]+m?$", var.cpu_request))
    error_message = "cpu_request must be a Kubernetes CPU quantity such as 250m or 1."
  }
}
variable "memory_request" {
  type        = string
  default     = "128Mi"
  description = "Memory request per pod"

  validation {
    condition     = can(regex("^[0-9]+(Ki|Mi|Gi)?$", var.memory_request))
    error_message = "memory_request must be a Kubernetes memory quantity such as 128Mi."
  }
}
variable "max_skew" {
  type        = number
  default     = 1
  description = "How unevenly the replicas may be spread across nodes, through a topologySpreadConstraint on kubernetes.io/hostname. Set with whenUnsatisfiable: ScheduleAnyway, so it steers placement without ever leaving a pod Pending - a hard constraint here would stop the Deployment from recovering onto the remaining nodes, which is the one thing the demo needs it to do"

  validation {
    condition     = var.max_skew >= 1
    error_message = "max_skew must be at least 1."
  }
}
variable "min_available" {
  type        = string
  default     = "50%"
  description = "How much of the Deployment a PodDisruptionBudget keeps available during a drain. The _monolithic template created no budget, so a drain could evict every replica at once. Set to null to get that back - which is worth doing once, to see the difference between a workload that survives a node going away and one that merely comes back"

  validation {
    condition     = var.min_available == null || can(regex("^([0-9]+|[0-9]{1,3}%)$", var.min_available))
    error_message = "min_available must be a count such as 6 or a percentage such as 50%, or null to create no budget."
  }
}
