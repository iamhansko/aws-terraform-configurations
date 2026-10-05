variable "release_name" {
  type        = string
  default     = "flux2"
  description = "Name of the Helm release. Also what \"helm list -n flux-system\" reports, which is the quickest way to tell a chart install from a bootstrapped one"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.release_name))
    error_message = "release_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "chart_repository" {
  type        = string
  default     = "https://fluxcd-community.github.io/helm-charts"
  description = "Helm repository the flux2 chart comes from. The community chart rather than an official one - Flux itself ships no chart, which is why bootstrapping is the upstream path and this is the alternative"

  validation {
    condition     = can(regex("^(https://|oci://)", var.chart_repository))
    error_message = "chart_repository must be an https:// or oci:// repository URL."
  }
}
variable "chart_version" {
  type        = string
  default     = "2.19.1"
  description = "Pinned flux2 chart version, which carries Flux 2.9.5. The _monolithic template piped fluxcd.io/install.sh into bash, so the Flux version was whatever was current on the day the instance booted"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.chart_version))
    error_message = "chart_version must be a semantic version."
  }
}
variable "namespace" {
  type        = string
  default     = "flux-system"
  description = "Namespace the controllers run in. flux-system is what the flux CLI and every Flux tutorial assume, and it is the namespace the controllers watch for their own custom resources"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "create_namespace" {
  type        = bool
  default     = true
  description = "Whether the release creates its own namespace. True because nothing else in this configuration declares it - a kubectl_manifest Namespace would have to be ordered before the release and would then be left behind by the release's own deletion"
}
variable "timeout_seconds" {
  type        = number
  default     = 600
  description = "How long the release waits for the controllers to become Available. It has to cover pulling four controller images onto a node that has just joined, which is most of this number"

  validation {
    condition     = var.timeout_seconds >= 60
    error_message = "timeout_seconds must be at least 60 - the release waits for the controller Deployments to become Available."
  }
}
variable "install_image_automation" {
  type        = bool
  default     = false
  description = "Whether the image reflector and image automation controllers are installed. Off by default: they watch container registries and write commits back to Git, which is a different demo and needs a token this half of the project does not use"
}
variable "install_notification_controller" {
  type        = bool
  default     = true
  description = "Whether the notification controller is installed. On, because it is what turns a reconciliation into an Event - so \"kubectl describe kustomization\" explains a failure rather than only reporting one"
}
variable "additional_set_values" {
  type = list(object({
    name  = string
    value = string
    type  = optional(string)
  }))
  default     = []
  description = "Extra chart values, appended to the ones above so a caller can reach a setting this module does not expose without being edited. type is \"auto\" when omitted; name it \"string\" for a value the chart must receive as a string rather than as an inferred bool or number (rules.md E-7)"

  validation {
    condition     = alltrue([for entry in var.additional_set_values : length(entry.name) > 0])
    error_message = "additional_set_values entries must each have a non-empty name."
  }
  validation {
    # helm_release's set only accepts these two, and the restriction is here rather than
    # discovered at apply (rules.md B-1/E-7).
    condition     = alltrue([for entry in var.additional_set_values : entry.type == null || contains(["auto", "string"], entry.type)])
    error_message = "additional_set_values type must be \"auto\", \"string\", or omitted."
  }
}
