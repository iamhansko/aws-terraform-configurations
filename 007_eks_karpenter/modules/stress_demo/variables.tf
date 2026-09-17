variable "name" {
  type        = string
  default     = "stress"
  description = "Name of the demo Deployment whose replica count drives Karpenter scale-up"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.name))
    error_message = "name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "namespace" {
  type        = string
  default     = "default"
  description = "Namespace the demo Deployment runs in"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "replica_count" {
  type        = number
  default     = 0
  description = "Replica count the Deployment is created with. Zero by default so applying this module provisions no EC2 capacity and costs nothing until the demo is run by scaling it up"

  validation {
    condition     = var.replica_count >= 0
    error_message = "replica_count must be zero or greater."
  }
}
variable "demo_replica_count" {
  type        = number
  default     = 6
  description = "Replica count the scale_up_command in the outputs uses. Not applied by Terraform: it only appears in the ready-to-run command, so the demo is driven from the instance rather than from an apply"

  validation {
    condition     = var.demo_replica_count > 0
    error_message = "demo_replica_count must be greater than zero."
  }
}
variable "image" {
  type        = string
  default     = "public.ecr.aws/eks-distro/kubernetes/pause:3.7"
  description = "Container image for the demo pods. pause does nothing and uses no CPU: the pods exist only to hold a CPU request that forces Karpenter to add capacity"

  validation {
    condition     = length(var.image) > 0
    error_message = "image must not be empty."
  }
}
variable "cpu_request" {
  type        = string
  default     = "1"
  description = "CPU request per pod. This is the number Karpenter's scheduling simulation works from, so it, not actual usage, is what makes nodes appear"

  validation {
    condition     = can(regex("^([0-9]+m|[0-9]+(\\.[0-9]+)?)$", var.cpu_request))
    error_message = "cpu_request must be a Kubernetes CPU quantity (e.g. 1 or 500m)."
  }
}
variable "termination_grace_period_seconds" {
  type        = number
  default     = 0
  description = "Grace period for the demo pods. Zero makes scale-down and the consolidation that follows it immediate, since these pods have nothing to shut down cleanly"

  validation {
    condition     = var.termination_grace_period_seconds >= 0
    error_message = "termination_grace_period_seconds must be zero or greater."
  }
}
variable "node_selector" {
  type        = map(string)
  description = "Labels a node must carry for these pods to be scheduled onto it. Passed in from the NodePool's own labels so the demo cannot drift onto the managed node group that hosts the controller (rules.md B-5)"

  validation {
    condition     = length(var.node_selector) > 0
    error_message = "node_selector must contain at least one label, otherwise the demo pods can be scheduled onto nodes Karpenter did not provision."
  }
}
variable "wait_for_rollout" {
  type        = bool
  default     = true
  description = "Whether the apply waits for the Deployment to finish rolling out. Harmless at the default replica_count of 0, which rolls out instantly; set false if creating the module with replicas already above zero, since the apply would then block until Karpenter has provisioned and joined the nodes"
}
