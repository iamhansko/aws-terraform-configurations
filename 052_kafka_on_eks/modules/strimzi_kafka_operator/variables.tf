variable "release_name" {
  type        = string
  default     = "strimzi-operator"
  description = "Name of the Helm release, strimzi-operator as eks-data-addons named it"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.release_name)) && length(var.release_name) <= 53
    error_message = "release_name must be a lowercase RFC 1123 label of 53 characters or fewer, as Helm requires."
  }
}
variable "namespace" {
  type        = string
  default     = "strimzi-kafka-operator"
  description = "Namespace the operator runs in, strimzi-kafka-operator as eks-data-addons defaulted it. The cluster-operator PodMonitor in modules/kafka_monitoring selects pods in this namespace, so it is passed there from this module's output"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a valid lowercase RFC 1123 label."
  }
}
variable "chart_repository" {
  type        = string
  default     = "https://strimzi.io/charts/"
  description = "Helm repository hosting the strimzi-kafka-operator chart"

  validation {
    condition     = can(regex("^(https://|oci://)", var.chart_repository))
    error_message = "chart_repository must be an https:// or oci:// URL."
  }
}
variable "chart_version" {
  type        = string
  default     = "0.46.0"
  description = "Version of the strimzi-kafka-operator chart, which is also the operator image tag. 0.46.0, as the blueprint pinned it. Each Strimzi release supports a short list of Kafka versions, so the Kafka version in modules/kafka_cluster has to be on this release's list - an unsupported one is accepted by the API server and then rejected by the operator, with the reason only in the Kafka resource's status"

  validation {
    condition     = can(regex("^0\\.[0-9]+\\.[0-9]+$", var.chart_version))
    error_message = "chart_version must be a 0.x.y semantic version, as Strimzi releases are numbered."
  }
}
variable "replica_count" {
  type        = number
  default     = 1
  description = "Number of operator replicas, one as the blueprint had it. Strimzi runs leader election, so more replicas add failover rather than throughput"

  validation {
    condition     = var.replica_count >= 1
    error_message = "replica_count must be at least 1."
  }
}
variable "node_selector" {
  type        = map(string)
  description = "nodeSelector for the operator pod. The blueprint pinned it to the core node group (NodeGroupType=core); the root passes that group's labels so the selector cannot drift from the nodes it names (rules.md B-5)"

  validation {
    condition     = length(var.node_selector) > 0
    error_message = "node_selector must not be empty. Without it the operator can land on a Karpenter node provisioned for something else."
  }
}
variable "cpu_request" {
  type        = string
  default     = "200m"
  description = "CPU request of the operator pod"

  validation {
    condition     = can(regex("^([0-9]+m|[0-9]+(\\.[0-9]+)?)$", var.cpu_request))
    error_message = "cpu_request must be a Kubernetes CPU quantity (e.g. 200m or 1)."
  }
}
variable "cpu_limit" {
  type        = string
  default     = "1000m"
  description = "CPU limit of the operator pod"

  validation {
    condition     = can(regex("^([0-9]+m|[0-9]+(\\.[0-9]+)?)$", var.cpu_limit))
    error_message = "cpu_limit must be a Kubernetes CPU quantity (e.g. 1000m or 1)."
  }
}
variable "memory_request" {
  type        = string
  default     = "384Mi"
  description = "Memory request of the operator pod"

  validation {
    condition     = can(regex("^[0-9]+(Ki|Mi|Gi)$", var.memory_request))
    error_message = "memory_request must be a Kubernetes binary quantity (e.g. 384Mi)."
  }
}
variable "memory_limit" {
  type        = string
  default     = "384Mi"
  description = "Memory limit of the operator pod"

  validation {
    condition     = can(regex("^[0-9]+(Ki|Mi|Gi)$", var.memory_limit))
    error_message = "memory_limit must be a Kubernetes binary quantity (e.g. 384Mi)."
  }
}
variable "timeout_seconds" {
  type        = number
  default     = 900
  description = "How long to wait for the operator Deployment to become Available, 900 as the blueprint had it"

  validation {
    condition     = var.timeout_seconds > 0
    error_message = "timeout_seconds must be greater than zero."
  }
}
