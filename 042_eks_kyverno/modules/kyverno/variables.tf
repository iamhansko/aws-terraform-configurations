variable "release_name" {
  type        = string
  default     = "kyverno"
  description = "Helm release name for Kyverno itself"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.release_name))
    error_message = "release_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "policies_release_name" {
  type        = string
  default     = "kyverno-policies"
  description = "Helm release name for the kyverno-policies chart, which carries the Pod Security Standard policies this project is about"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.policies_release_name))
    error_message = "policies_release_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "namespace" {
  type        = string
  default     = "kyverno"
  description = "Namespace Kyverno is installed into"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "create_namespace" {
  type        = bool
  default     = false
  description = "Whether this release creates the namespace. False by default because several releases share it and only one can own it"
}
variable "chart_repository" {
  type        = string
  default     = "https://kyverno.github.io/kyverno/"
  description = "Helm repository holding both the kyverno and kyverno-policies charts"

  validation {
    condition     = can(regex("^https://", var.chart_repository))
    error_message = "chart_repository must be an https URL."
  }
}
variable "chart_version" {
  type        = string
  default     = "3.5.2"
  description = "Pinned kyverno chart version. Pinned because Kyverno's admission webhooks sit in front of every pod creation in the cluster, so an unplanned upgrade can start rejecting workloads that used to be admitted"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.chart_version))
    error_message = "chart_version must be a semantic version."
  }
}
variable "policies_chart_version" {
  type        = string
  default     = "3.5.2"
  description = "Pinned kyverno-policies chart version. Kept in step with chart_version: the policies chart is published alongside Kyverno and expects a matching API"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.policies_chart_version))
    error_message = "policies_chart_version must be a semantic version."
  }
}
variable "enable_grafana_dashboard" {
  type        = bool
  default     = true
  description = "Whether Kyverno ships its Grafana dashboard as a ConfigMap. True, which is the point of running Grafana in this project: the dashboard reads the policy-report metrics Kyverno exports"
}
variable "pod_security_standard" {
  type        = string
  default     = "baseline"
  description = "Which Pod Security Standard the kyverno-policies chart enforces. baseline blocks the well-understood privilege escalations; restricted additionally requires dropping capabilities and running as non-root, which rejects most off-the-shelf images"

  validation {
    condition     = contains(["baseline", "restricted"], var.pod_security_standard)
    error_message = "pod_security_standard must be baseline or restricted - the two profiles the kyverno-policies chart publishes."
  }
}
variable "validation_failure_action" {
  type        = string
  default     = "Audit"
  description = "What the policies do on a violation. Audit records it in a PolicyReport and lets the pod through; Enforce rejects the pod. Audit by default because Enforce on a cluster that already has running workloads starts rejecting them at the next restart, and the demo is about seeing the reports"

  validation {
    condition     = contains(["Audit", "Enforce"], var.validation_failure_action)
    error_message = "validation_failure_action must be Audit or Enforce - Kyverno rejects any other value, and it is case-sensitive from 1.11 onwards."
  }
}
variable "timeout_seconds" {
  type        = number
  default     = 900
  description = "How long to wait for the releases. Kyverno registers admission webhooks and waits for its own controllers to be ready, which takes several minutes"

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
  description = "Extra values for the kyverno release. type is auto when omitted and may only be auto or string (rules.md E-7)"

  validation {
    condition     = alltrue([for v in var.additional_set_values : v.type == null || contains(["auto", "string"], v.type)])
    error_message = "additional_set_values type must be omitted, \"auto\" or \"string\"."
  }
}
