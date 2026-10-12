variable "namespace" {
  type        = string
  default     = "mwaa"
  description = "Namespace the KubernetesPodOperator DAG creates its pods in, as the blueprint named it"
  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.namespace)) && length(var.namespace) <= 63
    error_message = "namespace must be a valid lowercase RFC 1123 label of 63 characters or fewer."
  }
}
variable "role_name" {
  type        = string
  default     = "mwaa-role"
  description = "Name of the Role granting the MWAA execution role its permissions in the namespace, as the blueprint named it"
  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$", var.role_name))
    error_message = "role_name must be a valid lowercase RFC 1123 subdomain."
  }
}
variable "role_binding_name" {
  type        = string
  default     = "mwaa-role-binding"
  description = "Name of the RoleBinding tying the Role to the MWAA execution role's Kubernetes user, as the blueprint named it"
  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$", var.role_binding_name))
    error_message = "role_binding_name must be a valid lowercase RFC 1123 subdomain."
  }
}
variable "user_name" {
  type        = string
  default     = "mwaa-service"
  description = "Kubernetes user the MWAA execution role is authenticated as, and the RoleBinding's subject. The blueprint's aws-auth username; here the access entry's user_name, which the root reads back from this module's output so both sides use one value (rules.md B-5)"
  validation {
    # EKS rejects access entry user names under these prefixes.
    condition     = length(var.user_name) > 0 && !can(regex("^(system:|eks:|aws:|amazon:|iam:)", var.user_name))
    error_message = "user_name must not be empty and must not start with system:, eks:, aws:, amazon: or iam:, which EKS reserves."
  }
}
