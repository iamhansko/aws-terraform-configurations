variable "cluster_name" {
  type        = string
  description = "Name of the EKS cluster the controller manages load balancers for. Written into the chart's clusterName value, which the controller also uses to tag the load balancers it owns"

  validation {
    condition     = length(var.cluster_name) > 0
    error_message = "cluster_name must not be empty."
  }
}
variable "vpc_id" {
  type        = string
  description = "VPC ID the controller creates load balancers in. Passed explicitly so the controller does not have to discover it through IMDS"

  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must be a valid VPC ID (e.g. vpc-0123456789abcdef0)."
  }
}
variable "aws_region" {
  type        = string
  description = "AWS region the controller operates in"

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "aws_region must be a valid AWS region name (e.g. ap-northeast-2)."
  }
}
variable "oidc_provider_arn" {
  type        = string
  description = "ARN of the cluster's IAM OIDC provider, used as the Federated principal in the controller's IRSA trust policy"

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
  description = "Namespace the controller and its service account are installed into. Baked into the IRSA trust policy's sub condition, so it must match the Helm release's namespace"

  validation {
    condition     = length(var.namespace) > 0
    error_message = "namespace must not be empty."
  }
}
variable "service_account_name" {
  type        = string
  default     = "aws-load-balancer-controller"
  description = "Kubernetes service account name the controller runs as, annotated with the IRSA role ARN"

  validation {
    condition     = length(var.service_account_name) > 0
    error_message = "service_account_name must not be empty."
  }
}
variable "release_name" {
  type        = string
  default     = "aws-load-balancer-controller"
  description = "Name of the Helm release"

  validation {
    condition     = length(var.release_name) > 0
    error_message = "release_name must not be empty."
  }
}
variable "chart_repository" {
  type        = string
  default     = "https://aws.github.io/eks-charts"
  description = "Helm repository hosting the aws-load-balancer-controller chart"

  validation {
    condition     = can(regex("^(https://|oci://)", var.chart_repository))
    error_message = "chart_repository must be an https:// or oci:// URL."
  }
}
variable "chart_version" {
  type        = string
  default     = "1.14.1"
  description = "Version of the aws-load-balancer-controller Helm chart. Pinned rather than floating so a re-apply months later installs the same controller"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.chart_version))
    error_message = "chart_version must be a semantic version (e.g. 1.14.1)."
  }
}
variable "replica_count" {
  type        = number
  default     = 2
  description = "Number of controller replicas. The chart runs them as an active/standby leader-elected pair"

  validation {
    condition     = var.replica_count > 0
    error_message = "replica_count must be greater than zero."
  }
}
variable "timeout_seconds" {
  type        = number
  default     = 600
  description = "How long to wait for the controller's Deployment to become Available before failing the apply"

  validation {
    condition     = var.timeout_seconds > 0
    error_message = "timeout_seconds must be greater than zero."
  }
}
variable "additional_set_values" {
  type = list(object({
    name  = string
    value = string
  }))
  default     = []
  description = "Extra Helm values appended to the release's set list, for chart settings this module does not expose as named variables"

  validation {
    condition     = alltrue([for entry in var.additional_set_values : length(entry.name) > 0])
    error_message = "additional_set_values entries must each have a non-empty name."
  }
}
