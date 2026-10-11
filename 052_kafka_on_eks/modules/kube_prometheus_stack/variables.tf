variable "cluster_name" {
  type        = string
  description = "Name of the EKS cluster, used in the workspace alias and in resource descriptions"

  validation {
    condition     = length(var.cluster_name) > 0
    error_message = "cluster_name must not be empty."
  }
}
variable "aws_region" {
  type        = string
  description = "Region of the cluster and the workspace. Remote write signs its requests for this region, so it has to be the workspace's (rules.md I-3)"

  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]$", var.aws_region))
    error_message = "aws_region must look like an AWS region (e.g. ap-northeast-2)."
  }
}
variable "account_id" {
  type        = string
  description = "Account ID the IAM policy's resource ARNs are scoped to"

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be a 12-digit AWS account ID."
  }
}
variable "partition" {
  type        = string
  default     = "aws"
  description = "AWS partition the IAM policy's resource ARNs are written in"

  validation {
    condition     = contains(["aws", "aws-cn", "aws-us-gov"], var.partition)
    error_message = "partition must be aws, aws-cn or aws-us-gov."
  }
}
variable "oidc_provider_arn" {
  type        = string
  description = "ARN of the cluster's IAM OIDC provider, the Federated principal of the ingest role's trust policy"

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:oidc-provider/", var.oidc_provider_arn))
    error_message = "oidc_provider_arn must be an IAM OIDC provider ARN."
  }
}
variable "oidc_issuer_host" {
  type        = string
  description = "Cluster OIDC issuer URL without https://, used in the trust policy's condition keys"

  validation {
    condition     = length(var.oidc_issuer_host) > 0 && !can(regex("^https://", var.oidc_issuer_host))
    error_message = "oidc_issuer_host must be non-empty and must not include the https:// scheme."
  }
}
variable "release_name" {
  type        = string
  default     = "kube-prometheus-stack"
  description = "Name of the Helm release, kube-prometheus-stack as eks-blueprints-addons named it. The chart prefixes its objects with it, so the Grafana Service is <release_name>-grafana"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.release_name)) && length(var.release_name) <= 53
    error_message = "release_name must be a lowercase RFC 1123 label of 53 characters or fewer, as Helm requires."
  }
}
variable "namespace" {
  type        = string
  default     = "kube-prometheus-stack"
  description = "Namespace of the release, kube-prometheus-stack as eks-blueprints-addons defaulted it. The Grafana dashboards in modules/kafka_monitoring are created here, where the dashboard sidecar looks"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a valid lowercase RFC 1123 label."
  }
}
variable "chart_repository" {
  type        = string
  default     = "https://prometheus-community.github.io/helm-charts"
  description = "Helm repository hosting the kube-prometheus-stack chart"

  validation {
    condition     = can(regex("^(https://|oci://)", var.chart_repository))
    error_message = "chart_repository must be an https:// or oci:// URL."
  }
}
variable "chart_version" {
  type        = string
  default     = "48.1.1"
  description = "Version of the kube-prometheus-stack chart, 48.1.1 as the blueprint pinned it. Old - mid-2023 - and kept because it is what the blueprint ran; it renders against Kubernetes 1.34. Its CRDs are installed once and not upgraded by Helm, so moving to a newer major also means replacing the monitoring.coreos.com CRDs by hand"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.chart_version))
    error_message = "chart_version must be a three-part semantic version."
  }
}
variable "timeout_seconds" {
  type        = number
  default     = 900
  description = "How long the install may take, 900 as the blueprint had it"

  validation {
    condition     = var.timeout_seconds > 0
    error_message = "timeout_seconds must be greater than zero."
  }
}
variable "storage_class_name" {
  type        = string
  description = "StorageClass of Prometheus's volume claim. Passed from the module that created the class, so the claim cannot name one that does not exist and stay Pending (rules.md B-5)"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$", var.storage_class_name))
    error_message = "storage_class_name must be a valid lowercase RFC 1123 subdomain."
  }
}
variable "prometheus_storage_size" {
  type        = string
  default     = "50Gi"
  description = "Size of Prometheus's volume, 50Gi as the blueprint had it"

  validation {
    condition     = can(regex("^[0-9]+(Gi|Ti)$", var.prometheus_storage_size))
    error_message = "prometheus_storage_size must be a quantity such as 50Gi."
  }
}
variable "prometheus_retention" {
  type        = string
  default     = "5h"
  description = "How long Prometheus keeps samples locally, five hours as the blueprint had it. Short on purpose when remote write is on: Amazon Managed Prometheus holds the history"

  validation {
    condition     = can(regex("^[0-9]+(ms|s|m|h|d|w|y)$", var.prometheus_retention))
    error_message = "prometheus_retention must be a Prometheus duration such as 5h or 15d."
  }
}
variable "scrape_interval" {
  type        = string
  default     = "30s"
  description = "Default scrape interval, 30s as the blueprint had it"

  validation {
    condition     = can(regex("^[0-9]+(ms|s|m)$", var.scrape_interval))
    error_message = "scrape_interval must be a duration such as 30s."
  }
}
variable "evaluation_interval" {
  type        = string
  default     = "30s"
  description = "Rule evaluation interval, 30s as the blueprint had it"

  validation {
    condition     = can(regex("^[0-9]+(ms|s|m)$", var.evaluation_interval))
    error_message = "evaluation_interval must be a duration such as 30s."
  }
}
variable "scrape_timeout" {
  type        = string
  default     = "10s"
  description = "Default scrape timeout, 10s as the blueprint had it. Has to be shorter than scrape_interval, which Prometheus enforces at startup rather than here"

  validation {
    condition     = can(regex("^[0-9]+(ms|s|m)$", var.scrape_timeout))
    error_message = "scrape_timeout must be a duration such as 10s."
  }
}
variable "enable_amazon_prometheus" {
  type        = bool
  default     = true
  description = "Whether Prometheus remote-writes to an Amazon Managed Service for Prometheus workspace this module creates, and Grafana gets that workspace as a second data source. True, the blueprint's default. False installs the stack with local storage only, as the blueprint's kube-prometheus.yaml values did"
}
variable "amp_service_account_name" {
  type        = string
  default     = "amp-iamproxy-ingest-service-account"
  description = "Service account Prometheus and Grafana run as when enable_amazon_prometheus is true, named as the blueprint named it. The ingest role trusts exactly this name in this namespace"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$", var.amp_service_account_name))
    error_message = "amp_service_account_name must be a valid lowercase RFC 1123 subdomain."
  }
}
variable "grafana_admin_secret_name" {
  type        = string
  description = "Name of the Secrets Manager secret holding Grafana's admin password, <cluster>-grafana as the blueprint named it. Unique per account and region"

  validation {
    condition     = can(regex("^[A-Za-z0-9/_+=.@-]{1,512}$", var.grafana_admin_secret_name))
    error_message = "grafana_admin_secret_name must be 1-512 characters of the set Secrets Manager accepts in a secret name."
  }
}
