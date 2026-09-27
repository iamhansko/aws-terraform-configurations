variable "release_name" {
  type        = string
  default     = "kubecost"
  description = "Helm release name. The chart derives its Service name from it as <release_name>-cost-analyzer, which the Ingress below routes to"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.release_name))
    error_message = "release_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "namespace" {
  type        = string
  default     = "kubecost"
  description = "Namespace Kubecost is installed into"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "create_namespace" {
  type        = bool
  default     = false
  description = "Whether this release creates the namespace. False by default because the ingress controller is installed into the same namespace and is ordered first, so it owns it"
}
variable "chart" {
  type        = string
  default     = "oci://public.ecr.aws/kubecost/cost-analyzer"
  description = "Chart reference. An OCI reference from ECR Public, which is how Kubecost publishes for EKS; helm_release takes an oci:// chart with no repository argument"

  validation {
    condition     = can(regex("^(oci://|https://)", var.chart))
    error_message = "chart must be an oci:// reference or an https URL."
  }
}
variable "chart_version" {
  type        = string
  default     = "2.8.3"
  description = "Pinned Kubecost version. Also used to build the URL of the EKS values file below, so the two cannot drift to different versions"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.chart_version))
    error_message = "chart_version must be a semantic version, e.g. 2.8.3."
  }
}
variable "use_eks_cost_monitoring_values" {
  type        = bool
  default     = true
  description = "Whether to layer the chart's own values-eks-cost-monitoring.yaml on top. True reproduces what the _monolithic template did with 'helm -f <url>': it is the upstream preset that wires Kubecost to the EKS-optimised bundle. Fetched over HTTP at plan time, so an apply needs network access to raw.githubusercontent.com"
}
variable "service_port" {
  type        = number
  default     = 9090
  description = "Port the cost-analyzer Service listens on, which the Ingress routes to. 9090 is the chart's own default"

  validation {
    condition     = var.service_port > 0 && var.service_port <= 65535
    error_message = "service_port must be between 1 and 65535."
  }
}
variable "storage_class_name" {
  type        = string
  default     = null
  description = "Storage class for the bundled Prometheus volume. Null leaves the chart's default, which resolves to whichever StorageClass is marked cluster-default"

  validation {
    condition     = var.storage_class_name == null || can(regex("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$", var.storage_class_name))
    error_message = "storage_class_name must be a valid lowercase RFC 1123 subdomain, or null to leave the chart's own default. A name that matches no StorageClass leaves the claim Pending rather than failing, which times the release out instead of reporting the typo."
  }
}
variable "create_basic_auth" {
  type        = bool
  default     = true
  description = "Whether to put HTTP basic auth in front of the dashboard. True because Kubecost ships no authentication of its own, and this Ingress is internet-facing - without it the dashboard, and the cluster cost data in it, is readable by anyone who finds the address"
}
variable "basic_auth_user" {
  type        = string
  default     = "kubecost"
  description = "Username for the dashboard's basic auth"

  validation {
    condition     = can(regex("^[a-zA-Z0-9._-]+$", var.basic_auth_user))
    error_message = "basic_auth_user must be letters, digits, dots, underscores or hyphens - it goes into an htpasswd line, which is colon-separated."
  }
}
variable "basic_auth_password" {
  type        = string
  sensitive   = true
  description = "Password for the dashboard's basic auth. No default on purpose: the _monolithic template defaulted both user and password to 'kubecost', which is a working credential for an internet-facing dashboard committed to the repository. Pass it with TF_VAR_kubecost_basic_auth_password"

  validation {
    condition     = length(var.basic_auth_password) >= 8
    error_message = "basic_auth_password must be at least 8 characters."
  }
}
variable "basic_auth_secret_name" {
  type        = string
  default     = "basic-auth"
  description = "Name of the Secret holding the htpasswd file. The Ingress references it by name in its auth-secret annotation"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$", var.basic_auth_secret_name))
    error_message = "basic_auth_secret_name must be a valid lowercase Kubernetes object name."
  }
}
variable "basic_auth_realm" {
  type        = string
  default     = "Authentication Required"
  description = "Realm string the browser shows in its credential prompt"

  validation {
    condition     = length(var.basic_auth_realm) > 0
    error_message = "basic_auth_realm must not be empty."
  }
}
variable "ingress_name" {
  type        = string
  default     = "kubecost"
  description = "Name of the Ingress fronting the dashboard"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$", var.ingress_name))
    error_message = "ingress_name must be a valid lowercase Kubernetes object name."
  }
}
variable "ingress_class_name" {
  type        = string
  description = "IngressClass for the dashboard Ingress. Comes from the controller module that owns the class, so it cannot name a class no controller reconciles (rules.md B-5)"

  validation {
    condition     = length(var.ingress_class_name) > 0
    error_message = "ingress_class_name must not be empty."
  }
}
variable "timeout_seconds" {
  type        = number
  default     = 900
  description = "How long to wait for the release. Long because the chart brings its own Prometheus, which has to get a volume bound before it becomes ready"

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
