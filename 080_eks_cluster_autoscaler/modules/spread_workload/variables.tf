variable "name" {
  type        = string
  description = "Name of the Deployment and the value of the app label it selects on. No default: this module is instantiated once per topology key, and two instances sharing a name would fight over one object"

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
  description = "How many pods to run, twelve as the _monolithic template had it. This is the dial the demo turns: twelve pods at 100m each is 1.2 vCPU on top of whatever is already scheduled, which one t3.medium cannot hold - so the pods go Pending and the autoscaler has something to react to. Set it to 0 to watch the other half of the demo, where nodes become unneeded and are removed"

  validation {
    condition     = var.replicas >= 0
    error_message = "replicas must be zero or greater. Zero is deliberately allowed: it is how the scale-down half of the demo is triggered."
  }
}
variable "image" {
  type        = string
  description = "Container image. No default, because the two instances of this module use different images only so that the two Deployments are visibly distinct in kube-ops-view - nothing about either image matters otherwise"

  validation {
    condition     = can(regex(":[a-zA-Z0-9._-]+$|@sha256:[0-9a-f]{64}$", var.image))
    error_message = "image must carry an explicit tag or a digest."
  }
}
variable "topology_key" {
  type        = string
  description = "The node label the replicas are spread across. No default, because it is the whole reason this module is instantiated more than once: topology.kubernetes.io/zone balances across availability zones, kubernetes.io/hostname balances across individual nodes, and the two produce visibly different pictures on the same cluster"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?(/[a-zA-Z0-9]([-a-zA-Z0-9._]*[a-zA-Z0-9])?)?$", var.topology_key))
    error_message = "topology_key must be a valid Kubernetes label key, e.g. topology.kubernetes.io/zone."
  }
}
variable "max_skew" {
  type        = number
  default     = 1
  description = "How unevenly the replicas may be spread across the topology, one as the _monolithic template had it"

  validation {
    condition     = var.max_skew >= 1
    error_message = "max_skew must be at least 1."
  }
}
variable "when_unsatisfiable" {
  type        = string
  default     = "ScheduleAnyway"
  description = "What the scheduler does when the spread cannot be satisfied. ScheduleAnyway as the _monolithic template had it, and it is the right choice in a project about the autoscaler: DoNotSchedule leaves pods Pending for a reason the autoscaler cannot fix by adding a node, so a scale-up is triggered, the new node does not help, and the autoscaler keeps adding nodes until the group's maximum"

  validation {
    condition     = contains(["ScheduleAnyway", "DoNotSchedule"], var.when_unsatisfiable)
    error_message = "when_unsatisfiable must be ScheduleAnyway or DoNotSchedule."
  }
}
variable "cpu_request" {
  type        = string
  default     = "100m"
  description = "CPU request per pod, as the _monolithic template had it. This is what the autoscaler actually reasons about - it schedules against requests, not usage, so a pod requesting nothing never causes a scale-up no matter what it consumes"

  validation {
    condition     = can(regex("^[0-9]+m?$", var.cpu_request))
    error_message = "cpu_request must be a Kubernetes CPU quantity such as 100m or 1."
  }
}
variable "cpu_limit" {
  type        = string
  default     = "100m"
  description = "CPU limit per pod, as the _monolithic template had it"

  validation {
    condition     = can(regex("^[0-9]+m?$", var.cpu_limit))
    error_message = "cpu_limit must be a Kubernetes CPU quantity such as 100m or 1."
  }
}
variable "memory_request" {
  type        = string
  default     = "100Mi"
  description = "Memory request per pod, as the _monolithic template had it"

  validation {
    condition     = can(regex("^[0-9]+(Ki|Mi|Gi)$", var.memory_request))
    error_message = "memory_request must be a Kubernetes memory quantity such as 100Mi."
  }
}
variable "memory_limit" {
  type        = string
  default     = "100Mi"
  description = "Memory limit per pod, as the _monolithic template had it"

  validation {
    condition     = can(regex("^[0-9]+(Ki|Mi|Gi)$", var.memory_limit))
    error_message = "memory_limit must be a Kubernetes memory quantity such as 100Mi."
  }
}
