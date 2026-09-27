variable "release_name" {
  type        = string
  default     = "grafana-operator"
  description = "Helm release name for the operator itself"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.release_name))
    error_message = "release_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "namespace" {
  type        = string
  default     = "kyverno"
  description = "Namespace the operator and the Grafana instance live in"

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
variable "chart" {
  type        = string
  default     = "oci://ghcr.io/grafana/helm-charts/grafana-operator"
  description = "Chart reference. An OCI reference, which is how Grafana publishes the operator; helm_release takes an oci:// chart with no repository argument"

  validation {
    condition     = can(regex("^(oci://|https://)", var.chart))
    error_message = "chart must be an oci:// reference or an https URL."
  }
}
variable "chart_version" {
  type        = string
  default     = "v5.19.0"
  description = "Pinned grafana-operator version. Pinned because the operator owns the Grafana and GrafanaDatasource CRDs that the custom resources below are written against, and a version bump can change those schemas"

  validation {
    condition     = can(regex("^v?[0-9]+\\.[0-9]+\\.[0-9]+$", var.chart_version))
    error_message = "chart_version must be a semantic version, optionally prefixed with v."
  }
}
variable "grafana_instance_name" {
  type        = string
  default     = "grafana"
  description = "Name of the Grafana custom resource. The operator names the Service it creates grafana-service, independently of this"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$", var.grafana_instance_name))
    error_message = "grafana_instance_name must be a valid lowercase Kubernetes object name."
  }
}
variable "dashboard_label_value" {
  type        = string
  default     = "grafana"
  description = "Value of the 'dashboards' label on the Grafana instance. The operator matches dashboards and datasources to an instance by this label, so a datasource whose instanceSelector does not match it is created successfully and then attached to nothing"

  validation {
    condition     = length(var.dashboard_label_value) > 0
    error_message = "dashboard_label_value must not be empty."
  }
}
variable "admin_user" {
  type        = string
  default     = "admin"
  description = "Grafana admin username"

  validation {
    condition     = length(var.admin_user) > 0
    error_message = "admin_user must not be empty."
  }
}
variable "admin_password" {
  type        = string
  sensitive   = true
  description = "Grafana admin password. No default on purpose: the _monolithic template defaulted it to prom-operator and printed it in an output, which put a working credential for an internet-facing Grafana into the plan and the state file"

  validation {
    condition     = length(var.admin_password) >= 8
    error_message = "admin_password must be at least 8 characters."
  }
}
variable "service_name" {
  type        = string
  default     = "grafana-service"
  description = "Name of the Service the operator creates for the instance, which the Ingress routes to. Fixed by the operator rather than chosen here, so it is a variable only so a future operator version can be accommodated without editing the module"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$", var.service_name))
    error_message = "service_name must be a valid lowercase Kubernetes Service name."
  }
}
variable "service_port" {
  type        = number
  default     = 3000
  description = "Port the Grafana Service listens on"

  validation {
    condition     = var.service_port > 0 && var.service_port <= 65535
    error_message = "service_port must be between 1 and 65535."
  }
}
variable "ingress_class_name" {
  type        = string
  description = "IngressClass for the Grafana Ingress the operator creates. Comes from the controller module that owns the class, so it cannot name a class no controller reconciles (rules.md B-5)"

  validation {
    condition     = length(var.ingress_class_name) > 0
    error_message = "ingress_class_name must not be empty."
  }
}
variable "datasource_name" {
  type        = string
  default     = "prometheus"
  description = "Name of the GrafanaDatasource custom resource and of the datasource inside Grafana"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$", var.datasource_name))
    error_message = "datasource_name must be a valid lowercase Kubernetes object name."
  }
}
variable "prometheus_url" {
  type        = string
  description = "In-cluster URL of the Prometheus server the datasource reads from. Comes from the Prometheus module rather than being rebuilt here, so the datasource cannot point at a service name that does not exist (rules.md B-5)"

  validation {
    condition     = can(regex("^https?://", var.prometheus_url))
    error_message = "prometheus_url must be an http or https URL."
  }
}
variable "timeout_seconds" {
  type        = number
  default     = 600
  description = "How long to wait for the operator release. It has to register its CRDs and webhooks before any custom resource below can be created"

  validation {
    condition     = var.timeout_seconds > 0
    error_message = "timeout_seconds must be positive."
  }
}
