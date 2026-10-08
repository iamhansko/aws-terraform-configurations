variable "name" {
  type        = string
  default     = "kro-demo"
  description = "Name of the instance object"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.name))
    error_message = "name must be a valid lowercase RFC 1123 label."
  }
}

variable "namespace" {
  type        = string
  default     = "default"
  description = "Namespace the instance is created in. kro creates the Deployment and Service in the same namespace"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a valid lowercase RFC 1123 label."
  }
}

variable "api_version" {
  type        = string
  description = "Full apiVersion of the generated API, taken from the definition module's output rather than restated (rules.md B-5)"

  validation {
    condition     = can(regex("^kro\\.run/v[0-9]+((alpha|beta)[0-9]+)?$", var.api_version))
    error_message = "api_version must look like kro.run/v1alpha1."
  }
}

variable "kind" {
  type        = string
  description = "Kind of the generated API, taken from the definition module's output"

  validation {
    condition     = can(regex("^[A-Z][A-Za-z0-9]*$", var.kind))
    error_message = "kind must be UpperCamelCase."
  }
}

variable "workload_name" {
  type        = string
  default     = "kro-demo-nginx"
  description = "The one field this instance sets. The definition uses it to name the Deployment, the Service, and the pod label selector"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.workload_name))
    error_message = "workload_name must be a valid lowercase RFC 1123 label."
  }
}

variable "api_dependency" {
  type        = any
  default     = null
  description = "Value the caller passes purely to order this module after the step that confirms the generated CRD is served (rules.md D-5)"
}
