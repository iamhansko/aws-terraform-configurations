variable "name" {
  type        = string
  default     = "grafana"
  description = "Name of the Ingress, grafana as 052's post-install step named it"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$", var.name))
    error_message = "name must be a valid lowercase RFC 1123 subdomain."
  }
}
variable "namespace" {
  type        = string
  description = "Namespace of the Ingress, which has to be the Grafana Service's - an Ingress backend cannot name a Service in another namespace"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a valid lowercase RFC 1123 label."
  }
}
variable "service_name" {
  type        = string
  description = "Grafana Service the Ingress routes to. Passed from the kube-prometheus-stack module, which derives it from its release name (rules.md B-5)"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$", var.service_name))
    error_message = "service_name must be a valid lowercase RFC 1123 subdomain."
  }
}
variable "service_port" {
  type        = number
  description = "Port of the Grafana Service the backend names"

  validation {
    condition     = var.service_port > 0 && var.service_port < 65536
    error_message = "service_port must be a valid TCP port."
  }
}
variable "ingress_class_name" {
  type        = string
  default     = "alb"
  description = "IngressClass the AWS Load Balancer Controller watches"

  validation {
    condition     = length(var.ingress_class_name) > 0
    error_message = "ingress_class_name must not be empty."
  }
}
variable "annotations" {
  type        = map(string)
  description = "Annotations the controller reads - scheme, target type, frontend security group, health check. Supplied by the caller, because the security group ID comes from another module (rules.md B-6/G-1)"

  validation {
    condition     = alltrue([for key in keys(var.annotations) : length(key) > 0])
    error_message = "annotations keys must not be empty."
  }
}
