variable "namespace" {
  type        = string
  default     = "inflate"
  description = "Namespace the pressure workload runs in. A namespace of its own rather than default, so counting its pods and deleting the whole demo are both one command"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.namespace)) && length(var.namespace) <= 63
    error_message = "namespace must be a valid lowercase RFC 1123 DNS label of 63 characters or fewer."
  }
  validation {
    # This module creates the namespace, so naming a built-in one would have Terraform
    # adopt an object it did not create - and then delete it on destroy, which the API
    # server refuses for default and kube-system.
    condition     = !contains(["default", "kube-system", "kube-public", "kube-node-lease"], var.namespace)
    error_message = "namespace must not be one of the built-in namespaces (default, kube-system, kube-public, kube-node-lease); this module creates the namespace it is given and would delete it on destroy."
  }
}
variable "name" {
  type        = string
  default     = "inflate"
  description = "Name of the Deployment and the label its pods carry"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.name))
    error_message = "name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "replicas" {
  type        = number
  default     = 50
  description = "How many pods to ask for. This is the dial the demo turns: every pod consumes one VPC address, so raising it is what drives the nodes' own subnets empty and makes the CNI go looking for a tagged one. Raise it with terraform apply rather than kubectl scale, so the value stays in state and the next apply does not quietly put it back"

  validation {
    condition     = var.replicas >= 0
    error_message = "replicas must be zero or greater."
  }
}
variable "image" {
  type        = string
  default     = "public.ecr.aws/eks-distro/kubernetes/pause:3.7"
  description = "Container image for the pressure pods. pause does nothing and exits never, which is the point: the pod's only cost is the address it holds. It is still pulled over the network, so a pod that lands in a tagged subnet with no route out fails here - which is the symptom that catches a missing route table"

  validation {
    condition     = length(var.image) > 0
    error_message = "image must not be empty."
  }
}
variable "cpu_request" {
  type        = string
  default     = "50m"
  description = "CPU request per pod. Small on purpose: the demo wants to run out of addresses, not out of CPU, so the scheduler should keep packing pods onto the existing nodes rather than refusing to place them"

  validation {
    condition     = can(regex("^[0-9]+m?$", var.cpu_request))
    error_message = "cpu_request must be a Kubernetes CPU quantity such as 50m or 1."
  }
}
