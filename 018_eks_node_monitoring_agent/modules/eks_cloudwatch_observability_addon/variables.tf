variable "cluster_name" {
  type        = string
  description = "Name of the EKS cluster to install the amazon-cloudwatch-observability addon into"

  validation {
    condition     = length(var.cluster_name) > 0
    error_message = "cluster_name must not be empty."
  }
}
variable "pod_identity_role_arn" {
  type        = string
  description = "Role the CloudWatch agent's service account assumes through EKS Pod Identity. Needs CloudWatchAgentServerPolicy; the module receives an ARN and never learns who created the role (rules.md B-6)"

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:iam::[0-9]+:role/", var.pod_identity_role_arn))
    error_message = "pod_identity_role_arn must be an IAM role ARN."
  }
}
variable "service_account_name" {
  type        = string
  default     = "cloudwatch-agent"
  description = "Service account the association is bound to. The addon creates it with this name, so anything else leaves the agent without credentials and its logs stop with an AccessDenied"

  validation {
    condition     = var.service_account_name == "cloudwatch-agent"
    error_message = "service_account_name must be cloudwatch-agent - the only service account the amazon-cloudwatch-observability addon creates for its agent."
  }
}
variable "pod_identity_agent_dependency" {
  type        = any
  default     = null
  description = "Value to depend on so this addon is created after eks-pod-identity-agent. Pass that module's ARN output; nothing reads the value, it only carries the ordering (rules.md D-1)"
}
variable "addon_version" {
  type        = string
  default     = null
  description = "Specific addon version. When null, EKS picks the default for the cluster's Kubernetes version"

  validation {
    condition     = var.addon_version == null || can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+", var.addon_version))
    error_message = "addon_version must look like v4.7.0-eksbuild.1, or null."
  }
}
variable "resolve_conflicts_on_create" {
  type        = string
  default     = "OVERWRITE"
  description = "How to resolve field conflicts when creating the addon"

  validation {
    condition     = contains(["NONE", "OVERWRITE"], var.resolve_conflicts_on_create)
    error_message = "resolve_conflicts_on_create must be one of: NONE, OVERWRITE."
  }
}
variable "resolve_conflicts_on_update" {
  type        = string
  default     = "OVERWRITE"
  description = "How to resolve field conflicts when updating the addon. OVERWRITE because this module owns the Fluent Bit configuration - PRESERVE would keep whatever an operator edited in the cluster and quietly ignore changes made here"

  validation {
    condition     = contains(["NONE", "OVERWRITE", "PRESERVE"], var.resolve_conflicts_on_update)
    error_message = "resolve_conflicts_on_update must be one of: NONE, OVERWRITE, PRESERVE."
  }
}
