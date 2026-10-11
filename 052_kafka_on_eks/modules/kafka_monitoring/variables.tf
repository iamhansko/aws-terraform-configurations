variable "kafka_namespace" {
  type        = string
  description = "Namespace of the Kafka cluster. The PodMonitors are created here and three of them scrape here. Passed from modules/kafka_cluster's output, which also orders this module after the namespace exists"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.kafka_namespace))
    error_message = "kafka_namespace must be a valid lowercase RFC 1123 label."
  }
}
variable "operator_namespace" {
  type        = string
  description = "Namespace the Strimzi cluster operator runs in, which the cluster-operator PodMonitor scrapes"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.operator_namespace))
    error_message = "operator_namespace must be a valid lowercase RFC 1123 label."
  }
}
variable "grafana_namespace" {
  type        = string
  description = "Namespace Grafana's dashboard sidecar watches - the kube-prometheus-stack release's own"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.grafana_namespace))
    error_message = "grafana_namespace must be a valid lowercase RFC 1123 label."
  }
}
variable "dashboard_label_key" {
  type        = string
  default     = "grafana_dashboard"
  description = "Label the dashboard sidecar selects ConfigMaps by. grafana_dashboard is the kube-prometheus-stack chart's grafana.sidecar.dashboards.label default"

  validation {
    condition     = length(var.dashboard_label_key) > 0
    error_message = "dashboard_label_key must not be empty."
  }
}
variable "dashboard_label_value" {
  type        = string
  default     = "1"
  description = "Value of dashboard_label_key. A string: label values always are, and \"1\" is the chart's labelValue default"

  validation {
    condition     = can(regex("^[A-Za-z0-9]([-A-Za-z0-9_.]*[A-Za-z0-9])?$", var.dashboard_label_value))
    error_message = "dashboard_label_value must be a valid Kubernetes label value."
  }
}
