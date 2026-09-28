variable "operator_namespace" {
  type        = string
  default     = "opentelemetry-operator-system"
  description = "Namespace the ADOT add-on installs the OpenTelemetry Operator into. Every resourceName in the rules below refers to an object the add-on creates in this namespace, and the add-on's own choice of namespace is fixed - so changing this produces RBAC that grants access to names nothing will ever use, and the add-on install fails on the first object it cannot create"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.operator_namespace))
    error_message = "operator_namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "addon_manager_user" {
  type        = string
  default     = "eks:addon-manager"
  description = "Kubernetes user EKS acts as when it installs a managed add-on. Not a service account and not something this cluster creates: EKS authenticates as this name through the control plane, and the bindings below are what give it permission to create the operator. Getting it wrong leaves the bindings pointing at a user that never appears, and the add-on fails with a forbidden error naming this exact name"

  validation {
    condition     = length(var.addon_manager_user) > 0
    error_message = "addon_manager_user must not be empty."
  }
}
variable "cluster_role_name" {
  type        = string
  default     = "eks:addon-manager-otel"
  description = "Name of the cluster-scoped Role and its binding"

  validation {
    condition     = length(var.cluster_role_name) > 0
    error_message = "cluster_role_name must not be empty."
  }
}
variable "namespaced_role_name" {
  type        = string
  default     = "eks:addon-manager"
  description = "Name of the namespaced Role and its binding inside operator_namespace"

  validation {
    condition     = length(var.namespaced_role_name) > 0
    error_message = "namespaced_role_name must not be empty."
  }
}
