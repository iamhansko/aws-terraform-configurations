variable "admin_username" {
  type        = string
  default     = "admin"
  description = "Jenkins administrator login name"

  validation {
    condition     = length(var.admin_username) > 0
    error_message = "admin_username must not be empty."
  }
}

variable "admin_password" {
  type        = string
  sensitive   = true
  description = "Jenkins administrator password. Marked sensitive and passed through set_sensitive, so it stays out of plan output; it still ends up in the chart's Secret in the cluster"

  validation {
    condition     = length(var.admin_password) >= 8
    error_message = "admin_password must be at least 8 characters. The _monolithic template defaulted to \"jenkins\", which is a login anyone who can reach the load balancer can guess."
  }
}

variable "admin_email" {
  type        = string
  description = "Address Jenkins uses as the administrator contact"

  validation {
    condition     = can(regex("^[^@[:space:]]+@[^@[:space:]]+\\.[^@[:space:]]+$", var.admin_email))
    error_message = "admin_email must look like an email address."
  }
}

variable "ingress_class_name" {
  type        = string
  description = "IngressClass the Jenkins Ingress asks for. Has to be the class the ingress-nginx release in front of this one created, or no controller claims the Ingress and it never gets an address (rules.md G-1)"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$", var.ingress_class_name))
    error_message = "ingress_class_name must be a valid lowercase RFC 1123 subdomain."
  }
}

variable "ingress_hostname" {
  type        = string
  default     = null
  description = "Host the Ingress rule matches. Null leaves the rule hostless, which matches every request reaching the controller - correct while this is the only application behind it"

  validation {
    condition     = var.ingress_hostname == null || can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$", var.ingress_hostname))
    error_message = "ingress_hostname must be a valid lowercase DNS name, or null."
  }
}

variable "persistence_storage_class" {
  type        = string
  default     = null
  description = "StorageClass for the controller's PersistentVolumeClaim. Null uses the cluster's default class, which is what the gp3 class this project installs claims to be"

  validation {
    condition     = var.persistence_storage_class == null || can(regex("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$", var.persistence_storage_class))
    error_message = "persistence_storage_class must be a valid lowercase RFC 1123 subdomain, or null."
  }
}

variable "release_name" {
  type        = string
  default     = "jenkins"
  description = "Helm release name. Also the name of the Ingress and the Service the chart creates"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.release_name))
    error_message = "release_name must be a valid lowercase RFC 1123 label."
  }
}

variable "namespace" {
  type        = string
  default     = "jenkins"
  description = "Namespace the release is installed into. The same namespace as the ingress-nginx release in front of it, as the _monolithic script had them"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a valid lowercase RFC 1123 label."
  }
}

variable "create_namespace" {
  type        = bool
  default     = true
  description = "Whether Helm creates the namespace. True, as the _monolithic script's --create-namespace had it, and harmless when the ingress-nginx release already created it"
}

variable "chart_repository" {
  type        = string
  default     = "https://charts.jenkins.io"
  description = "Helm repository the Jenkins chart comes from"

  validation {
    condition     = can(regex("^https://", var.chart_repository))
    error_message = "chart_repository must be an https URL."
  }
}

variable "chart_version" {
  type        = string
  default     = "5.9.64"
  description = "Pinned Jenkins chart version. The _monolithic script ran `helm upgrade --install` with no --version"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.chart_version))
    error_message = "chart_version must be a three-part semantic version."
  }
}

variable "wait" {
  type        = bool
  default     = true
  description = "Whether the apply blocks until the controller is ready. True, as the _monolithic script's --wait had it: a Jenkins controller that cannot bind its volume is worth finding out about during the apply"
}

variable "timeout_seconds" {
  type        = number
  default     = 900
  description = "Helm operation timeout. Has to cover pulling the controller image and binding a fresh EBS volume"

  validation {
    condition     = var.timeout_seconds >= 300
    error_message = "timeout_seconds must be at least 300."
  }
}

variable "additional_set_values" {
  type = list(object({
    name  = string
    value = string
    type  = optional(string)
  }))
  default     = []
  description = "Extra chart values, for adding plugins or resource requests without editing the module"

  validation {
    condition     = alltrue([for entry in var.additional_set_values : entry.type == null || contains(["auto", "string"], entry.type)])
    error_message = "additional_set_values entries may only set type to \"auto\" or \"string\"; those are the two helm --set accepts (rules.md E-7)."
  }
}
