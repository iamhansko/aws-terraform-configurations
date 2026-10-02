variable "release_name" {
  type        = string
  default     = "aws-node-termination-handler"
  description = "Helm release name"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.release_name))
    error_message = "release_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "namespace" {
  type        = string
  default     = "kube-system"
  description = "Namespace the handler runs in, as the _monolithic template had it"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "chart" {
  type        = string
  default     = "oci://public.ecr.aws/aws-ec2/helm/aws-node-termination-handler"
  description = "OCI reference for the chart, as the _monolithic template had it. An OCI registry rather than an https repository, so helm takes the whole reference as the chart with no separate repository argument"

  validation {
    condition     = startswith(var.chart, "oci://")
    error_message = "chart must be an oci:// reference; an https repository needs a separate repository argument this module does not pass."
  }
}
variable "chart_version" {
  type        = string
  default     = "0.27.1"
  description = "Pinned chart version, where the _monolithic template pinned nothing. This component decides whether a node is drained before it disappears, so an unpinned upgrade changes behaviour at the worst possible moment"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.chart_version))
    error_message = "chart_version must be a semantic version (e.g. 0.27.1)."
  }
}
variable "enable_spot_interruption_draining" {
  type        = bool
  default     = true
  description = "Whether the handler drains a node on a spot interruption warning, as the _monolithic template had it. Note this overlaps with Karpenter's interruption queue - see the module's own comment for which nodes each one actually covers"
}
variable "enable_rebalance_monitoring" {
  type        = bool
  default     = true
  description = "Whether the handler watches for rebalance recommendations. A weaker signal than an interruption warning: it says the instance's capacity pool is at elevated risk, not that this instance is going"
}
variable "enable_rebalance_draining" {
  type        = bool
  default     = true
  description = "Whether a rebalance recommendation also drains the node, rather than only being recorded. On, as the _monolithic template had it - which trades some churn for fewer hard interruptions, since a rebalance recommendation usually precedes one"
}
variable "enable_scheduled_event_draining" {
  type        = bool
  default     = true
  description = "Whether the handler drains a node for a scheduled EC2 maintenance event. The slowest-moving of the signals it watches, and the only one that gives days of notice"
}
variable "timeout_seconds" {
  type        = number
  default     = 600
  description = "How long to wait for the DaemonSet to be ready"

  validation {
    condition     = var.timeout_seconds > 0
    error_message = "timeout_seconds must be positive."
  }
}
variable "additional_set_values" {
  type = list(object({
    name  = string
    value = string
    type  = optional(string)
  }))
  default     = []
  description = "Extra chart values. type is auto when omitted and may only be auto or string (rules.md E-7)"

  validation {
    condition     = alltrue([for v in var.additional_set_values : v.type == null || contains(["auto", "string"], v.type)])
    error_message = "additional_set_values type must be omitted, \"auto\" or \"string\"."
  }
}
