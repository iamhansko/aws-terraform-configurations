variable "name" {
  type        = string
  default     = "nginxapps.kro.run"
  description = "Name of the ResourceGraphDefinition. kro's convention is <plural>.<group>, matching the CRD it generates"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$", var.name))
    error_message = "name must be a valid lowercase DNS subdomain."
  }
}

variable "kind" {
  type        = string
  default     = "NginxApp"
  description = "Kind of the new API this definition creates. The cluster serves this kind once kro has processed the definition, which is why an instance of it cannot be applied in the same step"

  validation {
    condition     = can(regex("^[A-Z][A-Za-z0-9]*$", var.kind))
    error_message = "kind must be UpperCamelCase, as Kubernetes kinds are."
  }
}

variable "api_version" {
  type        = string
  default     = "v1alpha1"
  description = "Version of the new API. The group is always kro.run"

  validation {
    condition     = can(regex("^v[0-9]+((alpha|beta)[0-9]+)?$", var.api_version))
    error_message = "api_version must look like a Kubernetes API version (v1, v1alpha1, v1beta2)."
  }
}

variable "default_image" {
  type        = string
  default     = "public.ecr.aws/nginx/nginx:stable"
  description = "Default container image for instances of the new API. From the ECR public gallery rather than Docker Hub, whose anonymous pull limit is shared by every node in the region"

  validation {
    condition     = length(var.default_image) > 0
    error_message = "default_image must not be empty."
  }
}

variable "default_replicas" {
  type        = number
  default     = 2
  description = "Default replica count for instances of the new API"

  validation {
    condition     = var.default_replicas >= 1
    error_message = "default_replicas must be at least 1."
  }
}

variable "container_port" {
  type        = number
  default     = 80
  description = "Port the container listens on, and the Service's target port"

  validation {
    condition     = var.container_port > 0 && var.container_port <= 65535
    error_message = "container_port must be a valid TCP port."
  }
}

variable "service_port" {
  type        = number
  default     = 80
  description = "Port the Service exposes"

  validation {
    condition     = var.service_port > 0 && var.service_port <= 65535
    error_message = "service_port must be a valid TCP port."
  }
}

variable "capability_dependency" {
  type        = any
  default     = null
  description = "Value the caller passes purely to order this module after the kro capability. The ResourceGraphDefinition CRD does not exist until the capability has installed kro (rules.md D-4)"
}
