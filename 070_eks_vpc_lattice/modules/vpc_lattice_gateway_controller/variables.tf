variable "cluster_name" {
  type        = string
  description = "Name of the EKS cluster the controller manages VPC Lattice resources for. Also what the controller writes into the tags on the Lattice services and target groups it creates, which is how they can be told apart from another cluster's"

  validation {
    condition     = length(var.cluster_name) > 0
    error_message = "cluster_name must not be empty."
  }
}
variable "cluster_vpc_id" {
  type        = string
  description = "VPC the cluster's nodes are in. The controller associates this VPC with the Lattice service network, which is what makes pods able to resolve and reach the Lattice-assigned domain names"

  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.cluster_vpc_id))
    error_message = "cluster_vpc_id must be a valid VPC ID (e.g. vpc-0123456789abcdef0)."
  }
}
variable "aws_region" {
  type        = string
  description = "AWS region the controller creates VPC Lattice resources in"

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "aws_region must be a valid AWS region name (e.g. ap-northeast-2)."
  }
}
variable "aws_account_id" {
  type        = string
  description = "Account the controller operates in, which the chart needs in order to build the Lattice ARNs it looks resources up by"

  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "aws_account_id must be a 12-digit AWS account ID."
  }
}
variable "namespace" {
  type        = string
  default     = "aws-application-networking-system"
  description = "Namespace the controller is installed into, as the chart and the _monolithic template both have it. Also the namespace the Pod Identity association binds, so the two have to match"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "service_account_name" {
  type        = string
  default     = "gateway-api-controller"
  description = "Service account the controller runs as, and the one the Pod Identity association binds to the role. Decided by the chart rather than by this module - changing it does not rename anything, it only breaks the association, and the symptom is a controller that logs AccessDenied against every Lattice call"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$", var.service_account_name))
    error_message = "service_account_name must be a valid lowercase RFC 1123 subdomain."
  }
}
variable "release_name" {
  type        = string
  default     = "gateway-api-controller"
  description = "Name of the Helm release"

  validation {
    condition     = length(var.release_name) > 0
    error_message = "release_name must not be empty."
  }
}
variable "chart_repository" {
  type        = string
  default     = "oci://public.ecr.aws/aws-application-networking-k8s"
  description = "OCI registry holding the chart. public.ecr.aws serves anonymous pulls, so the \"aws ecr-public get-login-password | helm registry login\" step the _monolithic template ran before installing is not needed - and it was a step that had to succeed with credentials in a shell pipeline"

  validation {
    condition     = can(regex("^(oci://|https://)", var.chart_repository))
    error_message = "chart_repository must be an oci:// or https:// URL."
  }
}
variable "chart_name" {
  type        = string
  default     = "aws-gateway-controller-chart"
  description = "Chart name within the registry"

  validation {
    condition     = length(var.chart_name) > 0
    error_message = "chart_name must not be empty."
  }
}
variable "chart_version" {
  type        = string
  default     = "v1.1.5"
  description = "Pinned chart version, as the _monolithic template pinned it. The controller implements the Gateway API, so this and the Gateway API CRD release have to be a supported pair - a controller older than the CRDs ignores fields it does not know about rather than rejecting them"

  validation {
    condition     = can(regex("^v?[0-9]+\\.[0-9]+\\.[0-9]+$", var.chart_version))
    error_message = "chart_version must be a semantic version, optionally prefixed with v."
  }
}
variable "default_service_network" {
  type        = string
  description = "Name of the VPC Lattice service network the controller creates and associates the cluster's VPC with. No default: it has to be the name of the Gateway this project declares, because the controller matches them by name - a Gateway with no service network of that name gets no Lattice resources and reports nothing (rules.md B-5)"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.default_service_network))
    error_message = "default_service_network must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "webhook_enabled" {
  type        = bool
  default     = false
  description = "Whether the controller installs its pod-readiness-gate mutating webhook. False as the _monolithic template set it, and worth keeping false here for the same reason the AWS Load Balancer Controller's service mutator webhook is turned off elsewhere in this repository: a webhook with failurePolicy Fail and no namespaceSelector gates object creation cluster-wide on a controller pod being Ready (rules.md G-4)"
}
variable "iam_policy_statements_extra" {
  type = list(object({
    Effect   = string
    Action   = list(string)
    Resource = any
  }))
  default     = []
  description = "Extra statements appended to the controller's inline policy, for a caller that needs it to reach something this module does not grant. Empty by default: the statements below are what the controller's own documentation asks for, and widening them is the thing to avoid (rules.md A-5)"
}
variable "timeout_seconds" {
  type        = number
  default     = 600
  description = "How long to wait for the controller's Deployment to become Available. Generous because the controller creates the VPC Lattice service network and associates the VPC before it settles, and both are AWS-side operations"

  validation {
    condition     = var.timeout_seconds > 0
    error_message = "timeout_seconds must be greater than zero."
  }
}
