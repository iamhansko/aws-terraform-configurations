variable "cluster_name" {
  type        = string
  description = "Name of the EKS cluster whose managed node groups the autoscaler scales. Used as the chart's autoDiscovery.clusterName, which matches Auto Scaling groups tagged k8s.io/cluster-autoscaler/<cluster_name>"

  validation {
    condition     = length(var.cluster_name) > 0
    error_message = "cluster_name must not be empty."
  }
}
variable "aws_region" {
  type        = string
  description = "AWS region whose Auto Scaling groups the autoscaler queries"

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "aws_region must be a valid AWS region name (e.g. ap-northeast-2)."
  }
}
variable "oidc_provider_arn" {
  type        = string
  description = "ARN of the cluster's IAM OIDC provider, used as the Federated principal in the autoscaler's IRSA trust policy"

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
variable "namespace" {
  type        = string
  default     = "kube-system"
  description = "Namespace the autoscaler and its service account are installed into. Baked into the IRSA trust policy's sub condition, so it must match the Helm release's namespace"

  validation {
    condition     = length(var.namespace) > 0
    error_message = "namespace must not be empty."
  }
}
variable "service_account_name" {
  type        = string
  default     = "cluster-autoscaler"
  description = "Kubernetes service account name the autoscaler runs as, annotated with the IRSA role ARN"

  validation {
    condition     = length(var.service_account_name) > 0
    error_message = "service_account_name must not be empty."
  }
}
variable "release_name" {
  type        = string
  default     = "cluster-autoscaler"
  description = "Name of the Helm release"

  validation {
    condition     = length(var.release_name) > 0
    error_message = "release_name must not be empty."
  }
}
variable "chart_repository" {
  type        = string
  default     = "https://kubernetes.github.io/autoscaler"
  description = "Helm repository hosting the cluster-autoscaler chart"

  validation {
    condition     = can(regex("^(https://|oci://)", var.chart_repository))
    error_message = "chart_repository must be an https:// or oci:// URL."
  }
}
variable "chart_version" {
  type        = string
  default     = "9.51.0"
  description = "Version of the cluster-autoscaler Helm chart. The chart's default image tag tracks the Kubernetes minor version it was released for, so bump this together with the cluster's kubernetes_version"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.chart_version))
    error_message = "chart_version must be a semantic version (e.g. 9.51.0)."
  }
}
variable "balance_similar_node_groups" {
  type        = bool
  default     = true
  description = "Whether to keep node counts balanced across node groups with the same instance type and labels, which keeps this project's app and addon node groups from drifting into different sizes"
}
variable "skip_nodes_with_system_pods" {
  type        = bool
  default     = false
  description = "Whether to refuse to scale down nodes running kube-system pods. False lets the demo actually shrink, since with only a handful of nodes almost every one hosts some kube-system pod; leave true for production clusters without pod disruption budgets"
}
variable "scale_down_unneeded_time" {
  type        = string
  default     = "5m"
  description = "How long a node must be underutilized before it is removed. Shortened from the 10m upstream default so scale-down is observable during a demo"

  validation {
    condition     = can(regex("^[0-9]+(s|m|h)$", var.scale_down_unneeded_time))
    error_message = "scale_down_unneeded_time must be a Go duration such as 30s, 5m or 1h."
  }
}
variable "timeout_seconds" {
  type        = number
  default     = 600
  description = "How long to wait for the autoscaler's Deployment to become Available before failing the apply"

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
  description = "Extra Helm values appended to the release's set list, for chart settings this module does not expose as named variables. Set type = \"string\" on an entry whose value must stay a string, e.g. an annotation or label value of \"true\"/\"false\"/\"1\", which Helm would otherwise infer as a boolean or number and fail to decode (rules.md #33). Left unset, the entry keeps Helm's type inference"

  validation {
    condition     = alltrue([for entry in var.additional_set_values : length(entry.name) > 0])
    error_message = "additional_set_values entries must each have a non-empty name."
  }
  validation {
    condition     = alltrue([for entry in var.additional_set_values : entry.type == null || contains(["auto", "string"], entry.type)])
    error_message = "additional_set_values entry type must be either \"auto\" (Helm's type inference, the default when unset) or \"string\"."
  }
}
