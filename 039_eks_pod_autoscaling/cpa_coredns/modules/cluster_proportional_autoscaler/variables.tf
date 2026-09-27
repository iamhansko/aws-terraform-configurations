variable "release_name" {
  type        = string
  default     = "cluster-proportional-autoscaler"
  description = "Helm release name"
  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.release_name))
    error_message = "release_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "chart_repository" {
  type        = string
  default     = "https://kubernetes-sigs.github.io/cluster-proportional-autoscaler"
  description = "Chart repository URL"
  validation {
    condition     = can(regex("^(https?|oci)://", var.chart_repository))
    error_message = "chart_repository must be an http(s) or oci URL."
  }
}
variable "chart_version" {
  type        = string
  default     = "1.1.0"
  description = "Chart version, pinned so an upstream release cannot change what this project installs. The _monolithic template pinned nothing, so the same apply produced a different autoscaler depending on the day"
  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+", var.chart_version))
    error_message = "chart_version must be a semver version, e.g. 1.1.0."
  }
}
variable "namespace" {
  type        = string
  default     = "kube-system"
  description = "Namespace the autoscaler runs in. kube-system, the same namespace as its target: the chart grants scale permission through a Role, not a ClusterRole, so the autoscaler can only resize a Deployment in its own namespace"
  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "create_namespace" {
  type        = bool
  default     = false
  description = "Whether helm creates the namespace. False, because kube-system already exists"
}
variable "timeout_seconds" {
  type        = number
  default     = 600
  description = "How long helm waits for the release to become ready"
  validation {
    condition     = var.timeout_seconds > 0
    error_message = "timeout_seconds must be positive."
  }
}
variable "target" {
  type        = string
  default     = "deployment/coredns"
  description = "The workload the autoscaler resizes, in <kind>/<name> form. The chart rejects any kind other than deployment, replicationcontroller or replicaset at render time, so a typo here fails before anything is installed"
  validation {
    condition     = can(regex("^(deployment|replicationcontroller|replicaset)/[a-z0-9]([-a-z0-9.]*[a-z0-9])?$", var.target))
    error_message = "target must be <kind>/<name> where kind is deployment, replicationcontroller or replicaset, e.g. deployment/coredns."
  }
}
variable "nodes_per_replica" {
  type        = number
  default     = 2
  description = "How many nodes each replica of the target is expected to serve. The linear ladder: replicas = ceil(nodes / nodesPerReplica), clamped to min and max"
  validation {
    condition     = var.nodes_per_replica > 0
    error_message = "nodes_per_replica must be positive."
  }
}
variable "min_replicas" {
  type        = number
  default     = 2
  description = "Floor for the target's replica count. Two so DNS survives losing one node"
  validation {
    condition     = var.min_replicas >= 1
    error_message = "min_replicas must be at least 1."
  }
}
variable "max_replicas" {
  type        = number
  default     = 20
  description = "Ceiling for the target's replica count, as the _monolithic template set it. Without it a large node count turns linearly into a large number of DNS pods"
  validation {
    condition     = var.max_replicas >= 1
    error_message = "max_replicas must be at least 1."
  }
  validation {
    condition     = var.max_replicas >= var.min_replicas
    error_message = "max_replicas must be greater than or equal to min_replicas."
  }
}
variable "prevent_single_point_failure" {
  type        = bool
  default     = true
  description = "Whether the autoscaler keeps at least two replicas whenever there is more than one node, regardless of what the linear ladder computes. Guards against the ladder putting every DNS pod on one node"
}
variable "include_unschedulable_nodes" {
  type        = bool
  default     = true
  description = "Whether cordoned and unschedulable nodes count towards the node total. True, as the _monolithic template had it: it keeps a drain from shrinking DNS capacity at the same moment pods are being rescheduled onto fewer nodes"
}
variable "additional_set_values" {
  type = list(object({
    name  = string
    value = string
    type  = optional(string)
  }))
  default     = []
  description = "Extra helm values appended to the set list. type is auto when omitted, and only auto or string are accepted - a caller with no way to force a string could not pass an annotation value (rules.md E-7)"
  validation {
    condition     = alltrue([for entry in var.additional_set_values : entry.type == null || contains(["auto", "string"], entry.type)])
    error_message = "additional_set_values type must be auto or string when set."
  }
}
