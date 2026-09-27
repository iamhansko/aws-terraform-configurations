variable "release_name" {
  type        = string
  default     = "rancher"
  description = "Helm release name"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.release_name))
    error_message = "release_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "namespace" {
  type        = string
  default     = "cattle-system"
  description = "Namespace Rancher is installed into. cattle-system is what Rancher's own agents and its documentation assume, so it is not a free choice"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "chart_repository" {
  type        = string
  default     = "https://releases.rancher.com/server-charts/latest"
  description = "Helm repository holding the Rancher server chart. The 'latest' channel, as the _monolithic template used; 'stable' is the other published channel"

  validation {
    condition     = can(regex("^https://", var.chart_repository))
    error_message = "chart_repository must be an https URL."
  }
}
variable "chart_version" {
  type        = string
  default     = "2.12.2"
  description = "Pinned Rancher server version. Pinned rather than floating because Rancher's upgrade path is version-sensitive and the chart brings CRDs for its own management objects"

  validation {
    condition     = can(regex("^v?[0-9]+\\.[0-9]+\\.[0-9]+$", var.chart_version))
    error_message = "chart_version must be a semantic version, optionally prefixed with v."
  }
}
variable "hostname" {
  type        = string
  description = "The host Rancher serves on and puts in its Ingress. This has to be the address users actually reach, because Rancher redirects to it and rejects requests whose Host header does not match - here it is the pre-created load balancer's DNS name, which is knowable only because Terraform created that load balancer rather than leaving it to the controller (rules.md G-3)"

  validation {
    condition     = length(var.hostname) > 0
    error_message = "hostname must not be empty."
  }
}
variable "ingress_class_name" {
  type        = string
  description = "IngressClass for Rancher's Ingress. Comes from the ingress controller module that owns the class, so it cannot name a class no controller reconciles (rules.md B-5)"

  validation {
    condition     = length(var.ingress_class_name) > 0
    error_message = "ingress_class_name must not be empty."
  }
}
variable "bootstrap_password" {
  type        = string
  sensitive   = true
  description = "Rancher's first-login bootstrap password. No default on purpose: the _monolithic template defaulted it to 'rancher' and then printed it inside the dashboard URL as an output, which put a working administrator credential for an internet-facing Rancher into the plan, the state file and the instance README. Pass it with TF_VAR_rancher_bootstrap_password"

  validation {
    condition     = length(var.bootstrap_password) >= 12
    error_message = "bootstrap_password must be at least 12 characters. Rancher itself enforces 12 from 2.7 onwards and rejects a shorter one at install time."
  }
}
variable "replicas" {
  type        = number
  default     = 1
  description = "Rancher server replicas. One for a demo; the chart defaults to three, which needs three nodes to spread across and leaves pods Pending on a smaller cluster"

  validation {
    condition     = var.replicas >= 1
    error_message = "replicas must be at least 1."
  }
}
variable "timeout_seconds" {
  type        = number
  default     = 900
  description = "How long to wait for the release. Rancher takes several minutes to come up, and the chart waits on a Certificate that cert-manager has to issue first"

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
