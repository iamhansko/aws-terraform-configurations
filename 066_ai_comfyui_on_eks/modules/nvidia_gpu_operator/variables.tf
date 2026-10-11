variable "release_name" {
  type        = string
  default     = "nvidia-gpu-operator"
  description = "Name of the Helm release, nvidia-gpu-operator as the blueprint's GpuOperatorAddon named it"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.release_name))
    error_message = "release_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "namespace" {
  type        = string
  default     = "gpu-operator"
  description = "Namespace the operator and its operands run in, gpu-operator as the blueprint had it. Created by the release"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "chart_repository" {
  type        = string
  default     = "https://helm.ngc.nvidia.com/nvidia"
  description = "Helm repository holding the gpu-operator chart. NVIDIA's NGC repository, which is where its documentation installs from and which carries the same versions as the GitHub Pages mirror the blueprint's add-on defaulted to"

  validation {
    condition     = can(regex("^(https://|oci://)", var.chart_repository))
    error_message = "chart_repository must be an https:// or oci:// URL."
  }
}
variable "chart_version" {
  type        = string
  default     = "v26.3.2"
  description = "Pinned gpu-operator chart version, v26.3.2 as the blueprint pinned it. NVIDIA versions this chart with a leading v, unlike most charts (rules.md E-10)"

  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+$", var.chart_version))
    error_message = "chart_version must look like v26.3.2 - the gpu-operator chart's versions carry a leading v."
  }
}
variable "driver_enabled" {
  type        = bool
  default     = false
  description = "Whether the operator installs the NVIDIA driver. False, as the blueprint had it: the EKS-optimized AL2023 NVIDIA AMI Karpenter selects for a GPU instance already has the driver, and a second one loaded by the operator would fight it"
}
variable "toolkit_enabled" {
  type        = bool
  default     = false
  description = "Whether the operator installs the NVIDIA container toolkit. False, as the blueprint had it, for the same reason as driver_enabled: the AMI ships the toolkit and configures containerd for it"
}
variable "mig_strategy" {
  type        = string
  default     = "mixed"
  description = "How MIG-partitioned GPUs are advertised, mixed as the blueprint set it. Has no effect on the g5 and g6 instances the GPU pool allows, which do not support MIG"

  validation {
    condition     = contains(["none", "single", "mixed"], var.mig_strategy)
    error_message = "mig_strategy must be one of: none, single, mixed."
  }
}
variable "mig_manager_enabled" {
  type        = bool
  default     = true
  description = "Whether the MIG manager runs, as the blueprint had it. It only acts on MIG-capable GPUs"
}
variable "device_plugin_version" {
  type        = string
  default     = "v0.17.0"
  description = "Device plugin image version, v0.17.0 as the blueprint pinned it. Older than the v0.19.x this chart version ships by default; null leaves the chart's own choice in place (rules.md B-4)"

  validation {
    condition     = var.device_plugin_version == null || can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+$", coalesce(var.device_plugin_version, "v0.0.0")))
    error_message = "device_plugin_version must look like v0.17.0, or be null."
  }
}
variable "gfd_version" {
  type        = string
  default     = "v0.17.0"
  description = "GPU Feature Discovery image version, v0.17.0 as the blueprint pinned it. GFD ships from the same image as the device plugin, so the two are kept on the same version; null leaves the chart's own choice in place"

  validation {
    condition     = var.gfd_version == null || can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+$", coalesce(var.gfd_version, "v0.0.0")))
    error_message = "gfd_version must look like v0.17.0, or be null."
  }
}
variable "timeout_seconds" {
  type        = number
  default     = 900
  description = "How long to wait for the release's Deployments to become ready. The operator and node-feature-discovery run on the core nodes; the per-GPU DaemonSets have nothing to schedule until a GPU node exists, so they do not hold this up"

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
