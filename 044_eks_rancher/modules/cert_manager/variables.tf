variable "release_name" {
  type        = string
  default     = "cert-manager"
  description = "Helm release name"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.release_name))
    error_message = "release_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "namespace" {
  type        = string
  default     = "cert-manager"
  description = "Namespace cert-manager is installed into. Its own namespace, which is what the chart expects and what Rancher looks for"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "chart_repository" {
  type        = string
  default     = "https://charts.jetstack.io"
  description = "Helm repository holding the cert-manager chart"

  validation {
    condition     = can(regex("^https://", var.chart_repository))
    error_message = "chart_repository must be an https URL."
  }
}
variable "chart_version" {
  type        = string
  default     = "v1.16.2"
  description = "Pinned cert-manager version. Pinned because the chart installs CRDs that other charts build Certificate and Issuer objects against, and an unpinned upgrade can replace those CRDs underneath live objects"

  validation {
    condition     = can(regex("^v?[0-9]+\\.[0-9]+\\.[0-9]+$", var.chart_version))
    error_message = "chart_version must be a semantic version, optionally prefixed with v (e.g. v1.16.2)."
  }
}
variable "install_crds" {
  type        = bool
  default     = true
  description = "Whether the chart installs its CRDs. True, because Rancher creates a Certificate for its own ingress TLS and that object cannot be created before the CRD exists. Installing CRDs through the chart also means helm removes them on uninstall, which is the behaviour the _monolithic template's --set crds.enabled=true chose"
}
variable "timeout_seconds" {
  type        = number
  default     = 600
  description = "How long to wait for the release. cert-manager has to register its webhooks and pass its own readiness checks before anything can create an Issuer"

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
