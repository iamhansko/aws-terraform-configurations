variable "name" {
  type        = string
  default     = "nginx"
  description = "Name of the Deployment, of the PodDisruptionBudget, and of the label both select on"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.name))
    error_message = "name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "namespace" {
  type        = string
  default     = "default"
  description = "Namespace the Deployment and the budget live in, as the _monolithic template had it. Not created here - default already exists, and a module that created it would delete it on destroy"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "replicas" {
  type        = number
  default     = 3
  description = "How many pods to run, three as the _monolithic template had it - one per node in the default node group, which is what makes each node replacement during the update evict exactly one pod and so makes the budget's effect countable"

  validation {
    condition     = var.replicas >= 1
    error_message = "replicas must be at least 1."
  }
}
variable "image" {
  type        = string
  default     = "public.ecr.aws/nginx/nginx:1.29.5-alpine"
  description = "Container image. Pinned and from ECR Public, where the _monolithic template used the bare name \"nginx\" - which resolves to docker.io/library/nginx:latest: a floating tag on a registry that rate-limits anonymous pulls per source address. This demo replaces every node in the group and so pulls the image again on each new node, through one NAT gateway address per zone, which is the pattern that reaches the limit"

  validation {
    condition     = can(regex(":[a-zA-Z0-9._-]+$", var.image))
    error_message = "image must carry an explicit tag."
  }
}
variable "container_port" {
  type        = number
  default     = 80
  description = "Port the container listens on, and the port the readiness probe targets"

  validation {
    condition     = var.container_port > 0 && var.container_port <= 65535
    error_message = "container_port must be a valid TCP port."
  }
}
variable "readiness_initial_delay_seconds" {
  type        = number
  default     = 60
  description = "How long a new pod stays NotReady before its readiness probe is first run, sixty seconds as the _monolithic template had it. This is not incidental to the demo: a replacement pod counts against the budget until it turns Ready, so this number is the floor on how long each eviction step takes. Raise it and the update slows; raise it far enough and the upgrade phase hits its fifteen-minute drain timeout and fails with PodEvictionFailure"

  validation {
    condition     = var.readiness_initial_delay_seconds >= 0
    error_message = "readiness_initial_delay_seconds must be zero or greater."
  }
}
variable "readiness_period_seconds" {
  type        = number
  default     = 5
  description = "How often the readiness probe runs once the initial delay has passed"

  validation {
    condition     = var.readiness_period_seconds >= 1
    error_message = "readiness_period_seconds must be at least 1."
  }
}
variable "cpu_request" {
  type        = string
  default     = "250m"
  description = "CPU request per pod. The _monolithic template set no requests at all, which leaves the scheduler free to stack all three replicas onto one node - and then two of the three node replacements evict nothing, so the update finishes quickly and the budget appears to have done nothing"

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
  description = "How unevenly the replicas may be spread across nodes, through a topologySpreadConstraint on kubernetes.io/hostname. Set with whenUnsatisfiable: ScheduleAnyway so it steers placement without ever leaving a pod Pending - a hard constraint here would stop an evicted pod from being rescheduled while the node it came from is still cordoned, which would turn the budget's delay into a deadlock"

  validation {
    condition     = var.max_skew >= 1
    error_message = "max_skew must be at least 1."
  }
}
variable "pdb_max_unavailable" {
  type        = number
  default     = 1
  description = "How many of these pods may be unavailable at once, one as the _monolithic template had it. Counts only, no percentages: maxUnavailable is an IntOrString, and a quoted integer is read as a malformed percentage rather than as a number, so yamlencode has to be handed a real number here. Zero is valid and blocks every voluntary disruption, which is how to reach the PodEvictionFailure path on purpose. Set null and use pdb_min_available instead to express the same budget from the other side"

  validation {
    condition     = var.pdb_max_unavailable == null || var.pdb_max_unavailable >= 0
    error_message = "pdb_max_unavailable must be zero or greater, or null when pdb_min_available is used instead."
  }
}
variable "pdb_min_available" {
  type        = number
  default     = null
  description = "How many of these pods must stay available, as an alternative to pdb_max_unavailable. Counts only, for the same IntOrString reason. Setting it to the replica count is the other way to block every disruption"

  validation {
    condition     = var.pdb_min_available == null || var.pdb_min_available >= 0
    error_message = "pdb_min_available must be zero or greater, or null when pdb_max_unavailable is used instead."
  }

  validation {
    # A budget naming both is rejected by the API server, and a budget naming neither is
    # rejected too - so the pair is what has to be checked, not either value on its own
    # (rules.md B-1).
    condition     = (var.pdb_max_unavailable == null) != (var.pdb_min_available == null)
    error_message = "Exactly one of pdb_max_unavailable and pdb_min_available must be set: a PodDisruptionBudget may name maxUnavailable or minAvailable but not both, and must name one of them."
  }
}
