variable "name" {
  type        = string
  default     = "multi-homed"
  description = "Name of the Deployment and the value of the app label it selects on"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.name))
    error_message = "name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "namespace" {
  type        = string
  default     = "default"
  description = "Namespace the Deployment runs in, as the _monolithic template had it. Not created here - default already exists, and a module that created it would delete it on destroy"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "replicas" {
  type        = number
  default     = 1
  description = "How many pods to run, one as the _monolithic template had it. One is enough: the thing being demonstrated is visible inside a single pod, and every replica consumes one of the node's limited network-card slots"

  validation {
    condition     = var.replicas >= 1
    error_message = "replicas must be at least 1."
  }
}
variable "image" {
  type        = string
  default     = "registry.k8s.io/e2e-test-images/agnhost:2.39"
  description = "Container image, as the _monolithic template had it. agnhost is used purely as a shell to run ip or ifconfig inside: its ENTRYPOINT is /agnhost and its CMD is pause, so the manifest deliberately sets no command - giving it nothing to run would make it exit, restart and end up in CrashLoopBackOff"

  validation {
    condition     = can(regex(":[a-zA-Z0-9._-]+$|@sha256:[0-9a-f]{64}$", var.image))
    error_message = "image must carry an explicit tag or a digest."
  }
}
variable "image_pull_policy" {
  type        = string
  default     = "IfNotPresent"
  description = "Pull policy, as the _monolithic template had it"

  validation {
    condition     = contains(["Always", "IfNotPresent", "Never"], var.image_pull_policy)
    error_message = "image_pull_policy must be Always, IfNotPresent or Never."
  }
}
variable "nic_config_annotation_value" {
  type        = string
  default     = "multi-nic-attachment"
  description = "Value of the k8s.amazonaws.com/nicConfig annotation, which is the switch that asks the VPC CNI to give this pod an interface from a second network card. multi-nic-attachment is the only value the feature defines - it is a fixed token rather than a name pointing at another object, which is easy to misread. With the annotation absent the pod is created normally with one interface and nothing reports anything, which is why this is a variable with a validated value rather than a literal buried in the manifest"

  validation {
    condition     = var.nic_config_annotation_value == "multi-nic-attachment"
    error_message = "nic_config_annotation_value must be \"multi-nic-attachment\". It is the only value the EKS multi-NIC feature recognises; anything else is accepted by the API server as an ordinary annotation and the pod then gets a single interface, with no error anywhere to say why."
  }
}
variable "enable_multi_nic_annotation" {
  type        = bool
  default     = true
  description = "Whether the pod template carries the nicConfig annotation at all. True, because that annotation is the entire subject of this project. Set false to see the same Deployment without it - which is the honest way to compare, since the difference is visible only inside the pod (rules.md B-4)"
}
