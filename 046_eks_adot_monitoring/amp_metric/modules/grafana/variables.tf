variable "namespace" {
  type        = string
  default     = "monitoring"
  description = "Namespace the operator, Grafana and its custom resources live in, as the _monolithic template had it. Part of the IRSA trust policy's sub condition, so it has to match where the service account actually is"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "name" {
  type        = string
  default     = "grafana"
  description = "Name of the Grafana custom resource. The operator derives more from it than is obvious: the Deployment is <name>-deployment, the Service is <name>-service, and the service account is <name>-sa - so the IRSA trust policy and every check in the outputs are built from this one value (rules.md B-5)"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.name))
    error_message = "name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "operator_chart_version" {
  type        = string
  default     = "v5.19.0"
  description = "Pinned grafana-operator chart version, as the _monolithic template had it. The operator's version decides which apiVersion its custom resources use, so an unpinned upgrade can leave the Grafana and GrafanaDatasource objects here unrecognised"

  validation {
    condition     = can(regex("^v?[0-9]+\\.[0-9]+\\.[0-9]+$", var.operator_chart_version))
    error_message = "operator_chart_version must be a semantic version, optionally prefixed with v."
  }
}
variable "operator_chart" {
  type        = string
  default     = "oci://ghcr.io/grafana/helm-charts/grafana-operator"
  description = "OCI reference for the operator chart. An OCI registry rather than an https repository, which is how Grafana publishes it - helm takes the whole reference as the chart with no separate repository argument"

  validation {
    condition     = startswith(var.operator_chart, "oci://")
    error_message = "operator_chart must be an oci:// reference; an https repository needs a separate repository argument this module does not pass."
  }
}
variable "grafana_version" {
  type        = string
  default     = null
  description = "Grafana image tag the operator deploys. Null lets the operator pick the version it ships with, which is what the _monolithic template did"

  validation {
    condition     = var.grafana_version == null || can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.grafana_version))
    error_message = "grafana_version must be a semantic version, or null to use the operator's default."
  }
}
variable "admin_user" {
  type        = string
  default     = "admin"
  description = "Grafana administrator login name, as the _monolithic template had it"

  validation {
    condition     = length(var.admin_user) > 0
    error_message = "admin_user must not be empty."
  }
}
variable "admin_password" {
  type        = string
  default     = null
  sensitive   = true
  description = "Administrator password. Null generates one, which is the default and the better answer: the _monolithic template defaulted it to the literal string \"grafana\" and printed it in a Terraform output. Either way it reaches the container through a Secret and an environment variable rather than being written into the Grafana custom resource, where it would be readable to anyone who can get that object - and visible in plan, since a custom resource's body is not sensitive"

  validation {
    condition     = var.admin_password == null || length(var.admin_password) >= 8
    error_message = "admin_password must be at least 8 characters, or null to generate one."
  }
}
variable "secrets_manager_name" {
  type        = string
  default     = null
  description = "Optional Secrets Manager secret the generated credential is also written to, so it can be retrieved without reading Terraform state. Null skips it, in which case the password exists only in state and in the Kubernetes Secret"

  validation {
    condition     = var.secrets_manager_name == null || can(regex("^[a-zA-Z0-9/_+=.@-]{1,512}$", var.secrets_manager_name))
    error_message = "secrets_manager_name must be 1-512 characters of letters, digits and /_+=.@- , or null."
  }
}
variable "prometheus_endpoint" {
  type        = string
  description = "Base endpoint of the workspace Grafana queries, ending in a slash. Grafana's Prometheus data source takes the base URL - unlike a remote write exporter, which needs api/v1/remote_write appended - so this is the workspace's endpoint as-is"

  validation {
    condition     = can(regex("^https://", var.prometheus_endpoint))
    error_message = "prometheus_endpoint must be an https URL."
  }
  validation {
    condition     = !endswith(var.prometheus_endpoint, "remote_write")
    error_message = "prometheus_endpoint must be the workspace's base endpoint, not its remote write path. A data source pointed at api/v1/remote_write returns 405 on every query, which Grafana reports as a generic data source error."
  }
}
variable "prometheus_workspace_arn" {
  type        = string
  description = "ARN of the workspace, used to scope the query policy to it. Injected rather than looked up, so this module never learns how the workspace was configured (rules.md B-6)"

  validation {
    condition     = can(regex("^arn:aws:aps:", var.prometheus_workspace_arn))
    error_message = "prometheus_workspace_arn must be an Amazon Managed Prometheus workspace ARN."
  }
}
variable "aws_region" {
  type        = string
  description = "Region the data source signs its requests for. SigV4 signatures are region-scoped, so a wrong value here produces a signature AMP rejects - which Grafana shows as an authentication error rather than a configuration one"

  validation {
    condition     = can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]$", var.aws_region))
    error_message = "aws_region must be a valid AWS region name."
  }
}
variable "datasource_name" {
  type        = string
  default     = "amp"
  description = "Name of the data source inside Grafana, which is what appears in a dashboard's data source picker"

  validation {
    condition     = length(var.datasource_name) > 0
    error_message = "datasource_name must not be empty."
  }
}
variable "datasource_plugin" {
  type        = string
  default     = "grafana-amazonprometheus-datasource"
  description = "Grafana plugin backing the data source, as the _monolithic template had it. The Amazon Prometheus plugin rather than the built-in prometheus one, because only it does SigV4 signing - which is the whole reason the IRSA role below is needed. It also has to be installed, which is what GF_INSTALL_PLUGINS does"

  validation {
    condition     = length(var.datasource_plugin) > 0
    error_message = "datasource_plugin must not be empty."
  }
}
variable "iam_policy_arns" {
  type        = list(string)
  default     = ["arn:aws:iam::aws:policy/AmazonPrometheusQueryAccess"]
  description = "Managed policies attached to Grafana's IRSA role, as the _monolithic template had them. Note this grants query access to every workspace in the account rather than the one below - see inline_workspace_policy for the narrower form"

  validation {
    condition     = alltrue([for arn in var.iam_policy_arns : can(regex("^arn:aws:iam::", arn))])
    error_message = "iam_policy_arns must contain valid IAM policy ARNs."
  }
}
variable "inline_workspace_policy" {
  type        = bool
  default     = true
  description = "Whether to also attach an inline policy scoped to this one workspace. True, and iam_policy_arns can then be emptied: AmazonPrometheusQueryAccess grants aps:QueryMetrics on every workspace in the account, while this grants it on one. Keeping both is harmless and keeps the managed policy's name visible as the thing being replaced"
}
variable "ingress_class_name" {
  type        = string
  default     = "nginx"
  description = "IngressClass that decides which controller fulfils Grafana's Ingress. Passed in from the ingress controller module by the caller rather than defaulted blindly: a class no controller claims produces no error and no address at all (rules.md G-1)"

  validation {
    condition     = length(var.ingress_class_name) > 0
    error_message = "ingress_class_name must not be empty."
  }
}
variable "ingress_path" {
  type        = string
  default     = "/"
  description = "Path the Ingress routes to Grafana. Root, because this load balancer fronts nothing else - Grafana under a subpath also needs its own root_url and serve_from_sub_path settings, or it serves a page whose assets 404"

  validation {
    condition     = startswith(var.ingress_path, "/")
    error_message = "ingress_path must start with '/'."
  }
}
variable "service_port" {
  type        = number
  default     = 3000
  description = "Port Grafana's Service publishes, which the Ingress routes to. 3000 is what the operator creates"

  validation {
    condition     = var.service_port > 0 && var.service_port <= 65535
    error_message = "service_port must be a valid TCP port."
  }
}
variable "timeout_seconds" {
  type        = number
  default     = 600
  description = "How long the operator release may take. This waits for the operator only - the Grafana instance it then builds from the custom resource comes up asynchronously afterwards"

  validation {
    condition     = var.timeout_seconds > 0
    error_message = "timeout_seconds must be greater than zero."
  }
}
variable "oidc_provider_arn" {
  type        = string
  description = "ARN of the cluster's IAM OIDC provider, used as the Federated principal in Grafana's IRSA trust policy"

  validation {
    condition     = can(regex("^arn:aws:iam::", var.oidc_provider_arn))
    error_message = "oidc_provider_arn must be a valid IAM OIDC provider ARN."
  }
}
variable "oidc_issuer_host" {
  type        = string
  description = "Cluster OIDC issuer URL without the https:// scheme, used in the trust policy's sub/aud condition keys"

  validation {
    condition     = length(var.oidc_issuer_host) > 0 && !can(regex("^https://", var.oidc_issuer_host))
    error_message = "oidc_issuer_host must be non-empty and must not include the https:// scheme."
  }
}
