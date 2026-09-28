variable "cluster_name" {
  type        = string
  description = "Name of the EKS cluster to install the adot add-on into"

  validation {
    condition     = length(var.cluster_name) > 0
    error_message = "cluster_name must not be empty."
  }
}
variable "addon_version" {
  type        = string
  default     = null
  description = "Specific adot add-on version (e.g. v0.156.0-eksbuild.1). When null, EKS picks the default version for the cluster's Kubernetes version - which is what the _monolithic template did. Worth pinning for anything beyond a demo: the add-on's configuration schema is versioned with it, so a key that is valid today can be rejected by a later default"

  validation {
    condition     = var.addon_version == null || can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+-eksbuild\\.[0-9]+$", var.addon_version))
    error_message = "addon_version must look like v0.156.0-eksbuild.1, or null."
  }
}
variable "operator_namespace" {
  type        = string
  default     = "opentelemetry-operator-system"
  description = "Namespace the add-on installs the OpenTelemetry Operator and its collectors into. Part of every IRSA trust policy's sub condition here, so it has to match where the add-on actually puts them (rules.md B-5)"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.operator_namespace))
    error_message = "operator_namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "oidc_provider_arn" {
  type        = string
  description = "ARN of the cluster's IAM OIDC provider, used as the Federated principal in each collector's IRSA trust policy"

  validation {
    condition     = can(regex("^arn:aws:iam::", var.oidc_provider_arn))
    error_message = "oidc_provider_arn must be a valid IAM OIDC provider ARN."
  }
}
variable "oidc_issuer_host" {
  type        = string
  description = "Cluster OIDC issuer URL without the https:// scheme, used in the trust policies' sub/aud condition keys"

  validation {
    condition     = length(var.oidc_issuer_host) > 0 && !can(regex("^https://", var.oidc_issuer_host))
    error_message = "oidc_issuer_host must be non-empty and must not include the https:// scheme."
  }
}
variable "container_logs" {
  type = object({
    log_group_name  = string
    log_stream_name = optional(string, "adot")
    iam_policy_arns = optional(list(string), ["arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"])
  })
  default     = null
  description = "Enables the container logs collector, which reads container stdout and writes it to CloudWatch Logs. Null leaves that collector out of the add-on's configuration entirely, so the add-on installs the operator and nothing else. One of the three collector variables here has to be set - an add-on with no pipeline is an operator with nothing to reconcile"

  validation {
    condition     = var.container_logs == null || can(regex("^/[a-zA-Z0-9_./#-]{0,511}$", var.container_logs.log_group_name))
    error_message = "container_logs.log_group_name must be a valid CloudWatch log group name starting with '/'."
  }
  validation {
    condition = var.container_logs == null || alltrue([
      for arn in var.container_logs.iam_policy_arns : can(regex("^arn:aws:iam::", arn))
    ])
    error_message = "container_logs.iam_policy_arns must contain valid IAM policy ARNs."
  }
}
variable "prometheus_metrics" {
  type = object({
    remote_write_endpoint = string
    enable_amp            = optional(bool, true)
    enable_emf            = optional(bool, true)
    iam_policy_arns = optional(list(string), [
      "arn:aws:iam::aws:policy/AmazonPrometheusRemoteWriteAccess",
      "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy",
    ])
  })
  default     = null
  description = "Enables the Prometheus metrics collector, which scrapes pod metrics and remote-writes them. Two independent destinations: amp sends them to the endpoint below, emf sends them to CloudWatch as embedded metric format - which is why the default policy list carries both a Prometheus and a CloudWatch policy. Dropping one policy while leaving its pipeline enabled produces a collector that starts and silently fails to export"

  validation {
    condition     = var.prometheus_metrics == null || can(regex("^https://", var.prometheus_metrics.remote_write_endpoint))
    error_message = "prometheus_metrics.remote_write_endpoint must be an https URL. Note the Amazon Managed Prometheus workspace endpoint ends in a slash, and the remote write path is appended to it - the full value should end in api/v1/remote_write."
  }
  validation {
    condition     = var.prometheus_metrics == null || endswith(var.prometheus_metrics.remote_write_endpoint, "api/v1/remote_write")
    error_message = "prometheus_metrics.remote_write_endpoint must end in api/v1/remote_write. The workspace's own endpoint is only the prefix; pointing the exporter at it without the path produces 404s the collector logs and nothing else reports."
  }
  validation {
    condition     = var.prometheus_metrics == null || var.prometheus_metrics.enable_amp || var.prometheus_metrics.enable_emf
    error_message = "prometheus_metrics needs at least one of enable_amp or enable_emf; with both off the collector is created, scrapes nothing and exports nowhere."
  }
  validation {
    condition = var.prometheus_metrics == null || alltrue([
      for arn in var.prometheus_metrics.iam_policy_arns : can(regex("^arn:aws:iam::", arn))
    ])
    error_message = "prometheus_metrics.iam_policy_arns must contain valid IAM policy ARNs."
  }
}
variable "otlp_ingest" {
  type = object({
    enable_xray     = optional(bool, true)
    iam_policy_arns = optional(list(string), ["arn:aws:iam::aws:policy/AWSXrayWriteOnlyAccess"])
  })
  default     = null
  description = "Enables the OTLP ingest collector, which accepts traces over OTLP from instrumented applications and forwards them to X-Ray. Unlike the other two this collector is a Service applications send to rather than something that scrapes them, so an application has to be pointed at it - its endpoint is in the outputs"

  validation {
    condition = var.otlp_ingest == null || alltrue([
      for arn in var.otlp_ingest.iam_policy_arns : can(regex("^arn:aws:iam::", arn))
    ])
    error_message = "otlp_ingest.iam_policy_arns must contain valid IAM policy ARNs. Note the X-Ray write policy is AWSXrayWriteOnlyAccess - lowercase r in Xray, which IAM will not correct."
  }
}
variable "resolve_conflicts_on_create" {
  type        = string
  default     = "OVERWRITE"
  description = "How to resolve field value conflicts when creating an add-on that is migrating from a pre-existing self-managed installation"

  validation {
    condition     = contains(["NONE", "OVERWRITE"], var.resolve_conflicts_on_create)
    error_message = "resolve_conflicts_on_create must be one of: NONE, OVERWRITE."
  }
}
variable "resolve_conflicts_on_update" {
  type        = string
  default     = "OVERWRITE"
  description = "How to resolve field value conflicts when updating the add-on, as the _monolithic template set it"

  validation {
    condition     = contains(["NONE", "OVERWRITE", "PRESERVE"], var.resolve_conflicts_on_update)
    error_message = "resolve_conflicts_on_update must be one of: NONE, OVERWRITE, PRESERVE."
  }
}
