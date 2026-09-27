variable "release_name" {
  type        = string
  default     = "prometheus"
  description = "Helm release name. The chart derives its server Service name from it as <release_name>-server, which is the address the Grafana datasource points at - so this value reaches the datasource as configuration"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.release_name))
    error_message = "release_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "namespace" {
  type        = string
  default     = "kyverno"
  description = "Namespace Prometheus is installed into. The same namespace as Kyverno and Grafana here, which is what lets the datasource address stay a short in-namespace service name"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "create_namespace" {
  type        = bool
  default     = false
  description = "Whether this release creates the namespace. False by default because several releases share this namespace and only one of them can own it"
}
variable "chart_repository" {
  type        = string
  default     = "https://prometheus-community.github.io/helm-charts"
  description = "Helm repository holding the prometheus chart"

  validation {
    condition     = can(regex("^https://", var.chart_repository))
    error_message = "chart_repository must be an https URL."
  }
}
variable "chart_version" {
  type        = string
  default     = "27.40.0"
  description = "Pinned prometheus chart version"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.chart_version))
    error_message = "chart_version must be a semantic version."
  }
}
variable "server_port" {
  type        = number
  default     = 9090
  description = "Port the Prometheus server Service listens on, which the Grafana datasource URL uses. 9090 is the chart's own default"

  validation {
    condition     = var.server_port > 0 && var.server_port <= 65535
    error_message = "server_port must be between 1 and 65535."
  }
}
variable "persistent_volume_enabled" {
  type        = bool
  default     = false
  description = "Whether the Prometheus server claims a persistent volume. False because this cluster has no EBS CSI driver and no default StorageClass, so a claim would sit Pending forever and the release would time out. The cost is that metrics are lost when the pod restarts, which is acceptable for a policy-report demo"
}
variable "scrape_interval" {
  type        = string
  default     = "30s"
  description = "How often Prometheus scrapes its targets. The Kyverno dashboards read policy-report metrics, which change when a policy admits or rejects something rather than continuously"

  validation {
    condition     = can(regex("^[0-9]+[smh]$", var.scrape_interval))
    error_message = "scrape_interval must be a Prometheus duration such as 30s, 1m or 1h."
  }
}
variable "timeout_seconds" {
  type        = number
  default     = 600
  description = "How long to wait for the release"

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
