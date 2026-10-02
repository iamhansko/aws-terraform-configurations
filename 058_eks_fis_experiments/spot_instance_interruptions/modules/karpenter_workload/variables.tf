variable "name" {
  type        = string
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
variable "node_selector" {
  type        = map(string)
  description = "Labels a node must carry for these pods to land on it. Passed in from the node pool module rather than restated, because these are the labels that pool writes onto its nodes - a selector that matches nothing leaves every pod Pending, and Karpenter will not provision for it either, since it provisions for pending pods whose requirements it can satisfy and cannot satisfy a label no pool applies (rules.md B-5)"

  validation {
    condition     = length(var.node_selector) > 0
    error_message = "node_selector must not be empty; without it the pods land on the managed node group and the demo shows nothing about Karpenter."
  }
}
variable "replicas" {
  type        = number
  default     = 6
  description = "How many pods to run, six as the _monolithic template had it. The number is what forces Karpenter to provision: six pods with these resource requests do not fit on the managed node group, and none of them tolerates being there anyway because of the node selector"

  validation {
    condition     = var.replicas >= 1
    error_message = "replicas must be at least 1."
  }
}
variable "image" {
  type        = string
  default     = "public.ecr.aws/nginx/nginx:1.29.5-alpine"
  description = "Container image. Pinned and from ECR Public, where the _monolithic template used the bare name \"nginx\" - which resolves to docker.io/library/nginx:latest: a floating tag on a registry that rate-limits anonymous pulls per source address, and every node here shares one NAT gateway address per zone. A demo that deliberately replaces nodes pulls this image repeatedly, which is exactly the pattern that hits the limit"

  validation {
    condition     = can(regex(":[a-zA-Z0-9._-]+$", var.image))
    error_message = "image must carry an explicit tag."
  }
}
variable "cpu_request" {
  type        = string
  default     = "500m"
  description = "CPU request per pod. Large enough that the replicas do not all fit on one node, so the pool provisions more than one - which is what makes an interruption experiment interesting: there is somewhere for the evicted pods to go"

  validation {
    condition     = can(regex("^[0-9]+m?$", var.cpu_request))
    error_message = "cpu_request must be a Kubernetes CPU quantity such as 500m or 1."
  }
}
variable "memory_request" {
  type        = string
  default     = "512Mi"
  description = "Memory request per pod"

  validation {
    condition     = can(regex("^[0-9]+(Ki|Mi|Gi)?$", var.memory_request))
    error_message = "memory_request must be a Kubernetes memory quantity such as 512Mi."
  }
}
variable "min_available" {
  type        = string
  default     = "50%"
  description = "How much of the Deployment a PodDisruptionBudget keeps available during a voluntary disruption. The _monolithic template created no budget, which means a drain can evict every replica at once - so an interruption experiment shows the pods coming back rather than the workload staying up, which is the more interesting result. Set to null to skip the budget and get that behaviour back"

  validation {
    condition     = var.min_available == null || can(regex("^([0-9]+|[0-9]{1,3}%)$", var.min_available))
    error_message = "min_available must be a count such as 3 or a percentage such as 50%, or null to create no budget."
  }
}
