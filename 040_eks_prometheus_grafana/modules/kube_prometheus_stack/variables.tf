variable "release_name" {
  type        = string
  default     = "kube-prometheus"
  description = "Helm release name for the kube-prometheus-stack chart"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.release_name))
    error_message = "release_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "namespace" {
  type        = string
  default     = "monitoring"
  description = "Namespace the stack is installed into"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "create_namespace" {
  type        = bool
  default     = false
  description = "Whether this release creates the namespace. False, because this release cannot own it: it reads the ingress controllers' IngressClass names, so it is ordered after them, and they install into the same namespace. The caller creates the namespace as its own resource and orders every release after it. Left false as the default rather than true because a caller that forgets gets a loud 'namespaces \"<name>\" not found' on install, whereas several releases each believing they create it race over the same object"
}
variable "chart" {
  type        = string
  default     = "oci://ghcr.io/prometheus-community/charts/kube-prometheus-stack"
  description = "Chart reference. An OCI reference rather than a repository plus name, which is how prometheus-community publishes it now; helm_release takes an oci:// chart with no repository argument"

  validation {
    condition     = can(regex("^(oci://|https://)", var.chart)) || can(regex("^[a-z0-9-]+$", var.chart))
    error_message = "chart must be an oci:// reference, an https URL or a bare chart name."
  }
}
variable "chart_version" {
  type        = string
  default     = "77.14.0"
  description = "Pinned kube-prometheus-stack version. Pinned because this chart bundles Prometheus, Alertmanager, Grafana and a set of CRDs that move together, and an unpinned upgrade can replace CRDs underneath running objects"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.chart_version))
    error_message = "chart_version must be a semantic version, e.g. 77.14.0."
  }
}
variable "grafana_admin_user" {
  type        = string
  default     = "admin"
  description = "Grafana admin username"

  validation {
    condition     = length(var.grafana_admin_user) > 0
    error_message = "grafana_admin_user must not be empty."
  }
}
variable "grafana_admin_password" {
  type        = string
  sensitive   = true
  description = "Grafana admin password. No default on purpose: the _monolithic template shipped prom-operator as a plain default, which put a working credential for an internet-facing Grafana into every plan and state file. Pass it with TF_VAR_grafana_admin_password or a tfvars file kept out of git"

  validation {
    condition     = length(var.grafana_admin_password) >= 8
    error_message = "grafana_admin_password must be at least 8 characters."
  }
}
variable "grafana_ingress_class_name" {
  type        = string
  description = "IngressClass for the Grafana Ingress. Comes from the ingress controller module that owns the class, so the name cannot drift from a controller that actually exists (rules.md B-5)"

  validation {
    condition     = length(var.grafana_ingress_class_name) > 0
    error_message = "grafana_ingress_class_name must not be empty."
  }
}
variable "prometheus_ingress_class_name" {
  type        = string
  description = "IngressClass for the Prometheus Ingress"

  validation {
    condition     = length(var.prometheus_ingress_class_name) > 0
    error_message = "prometheus_ingress_class_name must not be empty."
  }
}
variable "alertmanager_ingress_class_name" {
  type        = string
  description = "IngressClass for the Alertmanager Ingress"

  validation {
    condition     = length(var.alertmanager_ingress_class_name) > 0
    error_message = "alertmanager_ingress_class_name must not be empty."
  }
}
variable "storage_class_name" {
  type        = string
  default     = null
  description = "Storage class for the Prometheus and Alertmanager persistent volumes. Null sends no storageSpec at all, leaving both on the chart's default of ephemeral storage. Any non-null value builds a full volumeClaimTemplate from this plus prometheus_storage_size and alertmanager_storage_size - the chart defaults none of those fields, so a partial template is an invalid PVC"

  validation {
    condition     = var.storage_class_name == null || can(regex("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$", var.storage_class_name))
    error_message = "storage_class_name must be a valid lowercase RFC 1123 subdomain, or null to leave the chart's own default. A name that matches no StorageClass leaves the claim Pending rather than failing, which times the release out instead of reporting the typo."
  }
}
variable "prometheus_storage_size" {
  type        = string
  default     = "20Gi"
  description = "Size of the Prometheus persistent volume. Required whenever storage_class_name is set: the chart has no default for it, and a volumeClaimTemplate without spec.resources.requests.storage is rejected by the API server with \"spec.resources[storage]: Required value\" - not at install time, but later, when the StatefulSet controller tries to create pod 0"

  validation {
    condition     = can(regex("^[0-9]+(Mi|Gi|Ti)$", var.prometheus_storage_size))
    error_message = "prometheus_storage_size must be a Kubernetes storage quantity such as 20Gi."
  }
}
variable "alertmanager_storage_size" {
  type        = string
  default     = "5Gi"
  description = "Size of the Alertmanager persistent volume. Smaller than Prometheus because Alertmanager stores silences and notification state rather than a metric history"

  validation {
    condition     = can(regex("^[0-9]+(Mi|Gi|Ti)$", var.alertmanager_storage_size))
    error_message = "alertmanager_storage_size must be a Kubernetes storage quantity such as 5Gi."
  }
}
variable "timeout_seconds" {
  type        = number
  default     = 900
  description = "How long to wait for the release. Long because the chart installs CRDs and then waits on Prometheus and Grafana to become ready, and Prometheus has to get a volume bound first"

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
