variable "namespace" {
  type        = string
  default     = "kube-system"
  description = "Namespace the Multus DaemonSet, its service account and its config map live in. kube-system, as the upstream manifest has it - a CNI DaemonSet that has to run on every node before pods can be networked belongs with the rest of the cluster's plumbing"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "name" {
  type        = string
  default     = "multus"
  description = "Name shared by the ServiceAccount, the ClusterRole and the ClusterRoleBinding, and the value of the name label the DaemonSet selects on"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.name))
    error_message = "name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "image" {
  type        = string
  description = "The Multus image, thick-plugin flavour. No default: it has to name the EKS image registry for the region the cluster is in, so the caller builds it from a pinned version and the current region rather than this module guessing. Pulling the us-west-2 registry from another region works and costs a cross-region transfer on every node"

  validation {
    condition     = can(regex(":[a-zA-Z0-9._-]+$|@sha256:[0-9a-f]{64}$", var.image))
    error_message = "image must carry an explicit tag or a digest."
  }
}
variable "master_cni_config_file" {
  type        = string
  default     = "10-aws.conflist"
  description = "The CNI config file Multus delegates the pod's primary interface to. 10-aws.conflist is what the VPC CNI writes on an EKS node, and this is the value that makes Multus an addition to it rather than a replacement. Wrong here and every pod on the node loses its primary interface - which is a cluster-wide outage rather than a failed demo"

  validation {
    condition     = can(regex("^[0-9]+-[a-z0-9-]+\\.conf(list)?$", var.master_cni_config_file))
    error_message = "master_cni_config_file must look like a CNI config file name, e.g. 10-aws.conflist."
  }
}
variable "cni_version" {
  type        = string
  default     = "0.3.1"
  description = "CNI specification version Multus writes into its generated configuration, as the upstream manifest has it. It has to be one the NetworkAttachmentDefinitions also declare"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.cni_version))
    error_message = "cni_version must be a semantic version such as 0.3.1."
  }
}
variable "log_level" {
  type        = string
  default     = "verbose"
  description = "Multus log level, verbose as the upstream manifest has it. Worth keeping: when a pod does not get its second interface, the reason is in /var/log/multus.log on the node and nowhere else"

  validation {
    condition     = contains(["panic", "error", "warning", "verbose", "debug"], var.log_level)
    error_message = "log_level must be one of panic, error, warning, verbose or debug."
  }
}
variable "cpu_request" {
  type        = string
  default     = "100m"
  description = "CPU request for the Multus daemon, as the upstream manifest sets it"

  validation {
    condition     = can(regex("^[0-9]+m?$", var.cpu_request))
    error_message = "cpu_request must be a Kubernetes CPU quantity such as 100m."
  }
}
variable "memory_request" {
  type        = string
  default     = "50Mi"
  description = "Memory request for the Multus daemon, as the upstream manifest sets it"

  validation {
    condition     = can(regex("^[0-9]+(Ki|Mi|Gi)$", var.memory_request))
    error_message = "memory_request must be a Kubernetes memory quantity such as 50Mi."
  }
}
