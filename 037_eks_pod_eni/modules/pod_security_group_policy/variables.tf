variable "vpc_id" {
  type        = string
  description = "VPC ID where the pod security group is created"

  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must be a valid VPC ID (e.g. vpc-0123456789abcdef0)."
  }
}

variable "security_group_name" {
  type        = string
  default     = "default-pod-sg"
  description = "Name of the security group directly assigned to pods via SecurityGroupPolicy"

  validation {
    condition     = length(var.security_group_name) > 0
    error_message = "security_group_name must not be empty."
  }
}

variable "namespace" {
  type        = string
  default     = "default"
  description = "Namespace the SecurityGroupPolicy (and the optional demo pod) is created in. SecurityGroupPolicy only matches pods in the same namespace"

  validation {
    condition     = length(var.namespace) > 0
    error_message = "namespace must not be empty."
  }
}

variable "policy_name" {
  type        = string
  default     = "default-sgp"
  description = "Name of the SecurityGroupPolicy custom resource"

  validation {
    condition     = length(var.policy_name) > 0
    error_message = "policy_name must not be empty."
  }
}

variable "create_demo_pod" {
  type        = bool
  default     = true
  description = "Whether to create a demo pod (dnsutils) to verify that the security group is attached via SecurityGroupPolicy"
}

variable "demo_pod_name" {
  type        = string
  default     = "dnsutils"
  description = "Name of the demo pod created when create_demo_pod is true"

  validation {
    condition     = length(var.demo_pod_name) > 0
    error_message = "demo_pod_name must not be empty."
  }
}

variable "demo_pod_image" {
  type        = string
  default     = "registry.k8s.io/e2e-test-images/agnhost:2.39"
  description = "Container image used by the demo pod created when create_demo_pod is true"

  validation {
    condition     = length(var.demo_pod_image) > 0
    error_message = "demo_pod_image must not be empty."
  }
}
