variable "name" {
  type        = string
  default     = "whereabouts"
  description = "Name of the DaemonSet, the ServiceAccount and the binding, as upstream names them. The ClusterRole gets a -cni suffix, also as upstream has it"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.name))
    error_message = "name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "namespace" {
  type        = string
  default     = "kube-system"
  description = "Namespace the DaemonSet runs in. kube-system, as upstream and as the Multus DaemonSet it serves"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "image" {
  type        = string
  default     = "ghcr.io/k8snetworkplumbingwg/whereabouts:v0.9.4"
  description = "whereabouts image. Pinned to a release tag rather than the :latest the upstream manifest carries - the plugin decides what address every secondary interface gets, which is a large thing to leave to whatever was pushed most recently. Unlike Multus, AWS publishes no EKS build of this, so it comes from the upstream registry and the nodes need egress to reach it"

  validation {
    condition     = can(regex(":[^:/]+$", var.image))
    error_message = "image must carry an explicit tag or digest - :latest by omission is what this default exists to avoid."
  }
  validation {
    condition     = !endswith(var.image, ":latest")
    error_message = "image must not be :latest. Pin a release tag, so the plugin that assigns every secondary address does not change underneath a node reboot."
  }
}
variable "log_level" {
  type        = string
  default     = "debug"
  description = "Log level for the ip-control-loop reconciler, debug as the upstream manifest has it. This is where an exhausted range or an address that could not be reclaimed is reported, and nothing else reports it"

  validation {
    condition     = contains(["debug", "verbose", "error", "panic"], var.log_level)
    error_message = "log_level must be one of debug, verbose, error or panic."
  }
}
variable "reconciler_cron_expression" {
  type        = string
  default     = "*/15 * * * *"
  description = "How often the reconciler sweeps the allocation store for addresses whose pod no longer exists. Upstream defaults to once a day at 04:30, which is reasonable for a cluster that runs for months and too slow for a demo that creates and deletes the same pods repeatedly - a range that small would show as exhausted long before the sweep ran"

  validation {
    condition     = length(split(" ", trimspace(var.reconciler_cron_expression))) == 5
    error_message = "reconciler_cron_expression must be a five-field cron expression (minute hour day-of-month month day-of-week)."
  }
}
variable "cpu_request" {
  type        = string
  default     = "100m"
  description = "CPU request and limit for the reconciler, as the upstream manifest sets them"

  validation {
    condition     = can(regex("^[0-9]+m?$", var.cpu_request))
    error_message = "cpu_request must be a Kubernetes CPU quantity (e.g. 100m or 1)."
  }
}
variable "memory_request" {
  type        = string
  default     = "100Mi"
  description = "Memory request for the reconciler, as the upstream manifest sets it"

  validation {
    condition     = can(regex("^[0-9]+(Ki|Mi|Gi)$", var.memory_request))
    error_message = "memory_request must be a Kubernetes memory quantity (e.g. 100Mi)."
  }
}
variable "memory_limit" {
  type        = string
  default     = "200Mi"
  description = "Memory limit for the reconciler, as the upstream manifest sets it. Higher than the request, unlike the CPU pair, which is how upstream has it"

  validation {
    condition     = can(regex("^[0-9]+(Ki|Mi|Gi)$", var.memory_limit))
    error_message = "memory_limit must be a Kubernetes memory quantity (e.g. 200Mi)."
  }
}
