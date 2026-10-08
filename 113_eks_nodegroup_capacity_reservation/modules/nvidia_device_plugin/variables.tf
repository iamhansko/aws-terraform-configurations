variable "release_name" {
  type        = string
  default     = "nvdp"
  description = "Name of the Helm release. It prefixes the DaemonSet name, which the diagnostic commands in this module's outputs rely on"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.release_name))
    error_message = "release_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "namespace" {
  type        = string
  default     = "kube-system"
  description = "Namespace the device plugin DaemonSet runs in. kube-system, because the plugin is a node-level component rather than a workload, and it already exists - so create_namespace stays false"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "chart_repository" {
  type        = string
  default     = "https://nvidia.github.io/k8s-device-plugin"
  description = "Helm repository holding the nvidia-device-plugin chart"

  validation {
    condition     = can(regex("^(https://|oci://)", var.chart_repository))
    error_message = "chart_repository must be an https:// or oci:// URL."
  }
}
variable "chart_version" {
  type        = string
  default     = "0.17.3"
  description = "Pinned nvidia-device-plugin chart version. Pinned rather than floating because the node affinity terms the caller has to match are a property of the chart version, not of Kubernetes - an unpinned upgrade that changed them would stop the DaemonSet from scheduling without anything in this configuration changing"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.chart_version))
    error_message = "chart_version must be a semantic version, e.g. 0.17.3."
  }
}
variable "enable_gpu_feature_discovery" {
  type        = bool
  default     = false
  description = <<-DESC
    Whether the chart also runs GPU Feature Discovery, which labels nodes with the GPU model, driver
    version and memory so a pod can ask for a particular kind of GPU rather than just one GPU.

    False here, which is the chart's own default, because this project runs one node of one reserved
    instance type - there is nothing to tell apart. It is not only a labelling convenience, though:
    it installs node-feature-discovery, and NFD is what sets the
    feature.node.kubernetes.io/pci-10de.present label that satisfies the DaemonSet's node affinity.
    So this is the alternative to labelling GPU nodes with nvidia.com/gpu.present directly, and a
    caller doing neither gets a DaemonSet that schedules nothing (rules.md B-4).
  DESC
}
variable "timeout_seconds" {
  type        = number
  default     = 600
  description = "How long to wait for the plugin's DaemonSet to report ready. Generous because the pod pulls its image through a NAT gateway from a private subnet"

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
  description = "Extra chart values. type is auto when omitted and may only be auto or string, so a caller can force a value the chart must receive as a string (rules.md E-7)"

  validation {
    condition     = alltrue([for v in var.additional_set_values : v.type == null || contains(["auto", "string"], v.type)])
    error_message = "additional_set_values type must be omitted, \"auto\" or \"string\" - the only values helm_release accepts."
  }
}
