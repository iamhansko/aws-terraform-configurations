variable "release_name" {
  type        = string
  default     = "argo-rollouts"
  description = "Helm release name"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.release_name))
    error_message = "release_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "namespace" {
  type        = string
  default     = "argo-rollouts"
  description = "Namespace the controller runs in. The chart's default, and the namespace 'kubectl argo rollouts' looks in unless told otherwise"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "chart_repository" {
  type        = string
  default     = "https://argoproj.github.io/argo-helm"
  description = "Helm repository holding the argo-rollouts chart"

  validation {
    condition     = can(regex("^(https://|oci://)", var.chart_repository))
    error_message = "chart_repository must be an https:// or oci:// URL."
  }
}
variable "chart_name" {
  type        = string
  default     = "argo-rollouts"
  description = "Chart name"

  validation {
    condition     = length(var.chart_name) > 0
    error_message = "chart_name must not be empty."
  }
}
variable "chart_version" {
  type        = string
  default     = "2.40.4"
  description = "Chart version, pinned rather than tracking latest. The _monolithic template ran an install script from a cloned repository, so which version arrived depended on the day the demo was run"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.chart_version))
    error_message = "chart_version must be a semantic version (e.g. 2.40.4)."
  }
}
variable "dashboard_enabled" {
  type        = bool
  default     = true
  description = "Whether to install the Argo Rollouts dashboard. On because a blue/green promotion is far easier to follow in the dashboard than in kubectl output; reach it with 'kubectl argo rollouts dashboard' or a port-forward from the bastion"
}
variable "controller_replica_count" {
  type        = number
  default     = 1
  description = "Number of controller replicas. One is enough for a demo; the controller leader-elects, so more than one only buys failover"

  validation {
    condition     = var.controller_replica_count > 0
    error_message = "controller_replica_count must be greater than zero."
  }
}
variable "timeout_seconds" {
  type        = number
  default     = 600
  description = "How long to wait for the controller Deployment to become Available before failing the apply"

  validation {
    condition     = var.timeout_seconds > 0
    error_message = "timeout_seconds must be greater than zero."
  }
}
variable "additional_set_values" {
  type = list(object({
    name  = string
    value = string
    type  = optional(string)
  }))
  default     = []
  description = "Extra Helm values appended to the release's set list, for chart settings this module does not expose as named variables"

  validation {
    condition     = alltrue([for entry in var.additional_set_values : length(entry.name) > 0])
    error_message = "additional_set_values entries must each have a non-empty name."
  }
  validation {
    condition     = alltrue([for entry in var.additional_set_values : entry.type == null || contains(["auto", "string"], entry.type)])
    error_message = "additional_set_values[*].type must be auto or string - the two values helm_release's set accepts. Use string for a value the chart puts into an annotation or label, which must be a string rather than an inferred bool or number (rules.md E-7)."
  }
}
