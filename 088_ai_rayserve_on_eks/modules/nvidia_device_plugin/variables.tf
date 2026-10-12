variable "release_name" {
  type        = string
  default     = "nvdp"
  description = "Name of the Helm release, nvdp as the _monolithic template named it"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.release_name))
    error_message = "release_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "namespace" {
  type        = string
  default     = "kube-system"
  description = "Namespace the device plugin DaemonSet runs in, as the _monolithic template had it. Also where the time-slicing config map has to live, because the plugin reads it from its own namespace"

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
  description = "Pinned nvidia-device-plugin chart version. The _monolithic template ran helm repo update and installed whatever was current at boot time, so two applies weeks apart advertised GPUs through different plugin versions - and the time-slicing configuration format is a property of that version"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.chart_version))
    error_message = "chart_version must be a semantic version, e.g. 0.17.3."
  }
}
variable "enable_gpu_feature_discovery" {
  type        = bool
  default     = true
  description = "Whether the chart also runs GPU Feature Discovery, as the _monolithic template's --set gfd.enabled=true did. It labels nodes with the GPU model, driver version and memory, which is what lets a pod ask for a particular kind of GPU rather than just one GPU"
}
variable "time_slicing_replicas" {
  type        = number
  default     = null
  description = "How many slices each physical GPU is advertised as. Null installs the plugin without time slicing, so one GPU is one nvidia.com/gpu and a second pod asking for one stays Pending. Set it - four, as the _monolithic template's config map did - and the same GPU is advertised as that many, so several pods share it by taking turns. Nothing about the sharing is enforced: the slices are time slices on the same hardware, so four pods each get roughly a quarter of the throughput and all of the memory pressure (rules.md B-4)"

  validation {
    condition     = var.time_slicing_replicas == null || var.time_slicing_replicas >= 2
    error_message = "time_slicing_replicas must be at least 2, or null to install the plugin without time slicing. One slice per GPU is what not setting it already does."
  }
}
variable "config_map_name" {
  type        = string
  default     = "nvdp-config"
  description = "Name of the config map the plugin reads its time-slicing configuration from, as the _monolithic template named it. Ignored when time_slicing_replicas is null, in which case no config map is created and the chart is not pointed at one"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$", var.config_map_name))
    error_message = "config_map_name must be a valid lowercase RFC 1123 subdomain."
  }
}
variable "timeout_seconds" {
  type        = number
  default     = 600
  description = "How long to wait for the plugin's DaemonSet to become ready. Generous because the GPU nodes have to be up first, and an AL2023 NVIDIA node takes noticeably longer to join than a plain one"

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
