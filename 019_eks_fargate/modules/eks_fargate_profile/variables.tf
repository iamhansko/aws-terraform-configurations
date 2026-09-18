variable "cluster_name" {
  type        = string
  description = "Name of the EKS cluster this Fargate profile belongs to"

  validation {
    condition     = length(var.cluster_name) > 0
    error_message = "cluster_name must not be empty."
  }
}
variable "profile_name" {
  type        = string
  description = "Name of the EKS Fargate profile"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-_]{0,99}$", var.profile_name))
    error_message = "profile_name must start with a letter or digit and contain only letters, digits, hyphens and underscores (100 characters or fewer)."
  }
}
variable "namespace" {
  type        = string
  description = "Kubernetes namespace this profile selects. Every pod scheduled into it runs on Fargate instead of a node"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "subnet_ids" {
  type        = list(string)
  description = "Subnets Fargate places pod ENIs in. Private subnets only - Fargate does not support public subnets, and the create call fails rather than silently placing pods somewhere else"

  validation {
    condition     = length(var.subnet_ids) > 0 && alltrue([for s in var.subnet_ids : can(regex("^subnet-[0-9a-f]+$", s))])
    error_message = "subnet_ids must contain at least one valid subnet ID (e.g. subnet-0123456789abcdef0)."
  }
}
variable "pod_execution_policy_arn" {
  type        = string
  default     = "arn:aws:iam::aws:policy/AmazonEKSFargatePodExecutionRolePolicy"
  description = "Managed policy attached to the pod execution role. This is the policy that lets Fargate pull images and write pod logs on the pods' behalf; EKS rejects a profile whose role does not carry it"

  validation {
    condition     = can(regex("^arn:aws:iam::", var.pod_execution_policy_arn))
    error_message = "pod_execution_policy_arn must be a valid IAM policy ARN."
  }
}
