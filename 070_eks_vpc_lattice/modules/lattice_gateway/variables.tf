variable "name" {
  type        = string
  default     = "eks-network"
  description = "Name of the Gateway, eks-network as the _monolithic template had it. It has to equal the controller's defaultServiceNetwork: the controller pairs the two by name, and a Gateway naming a service network that does not exist never gets an address and reports nothing"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.name))
    error_message = "name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "namespace" {
  type        = string
  default     = "default"
  description = "Namespace the Gateway lives in, as the _monolithic template had it. An HTTPRoute in another namespace can only attach to it if the Gateway's listener allows that namespace, which the default here does not - so routes belong in this namespace too"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "gateway_class_name" {
  type        = string
  default     = "amazon-vpc-lattice"
  description = "Name of the GatewayClass this module creates and the Gateway asks for. One value for both, so the Gateway cannot name a class that was never created - which would leave it unreconciled by anything"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.gateway_class_name))
    error_message = "gateway_class_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "controller_name" {
  type        = string
  default     = "application-networking.k8s.aws/gateway-api-controller"
  description = "The controller the GatewayClass points at, which is the string the AWS Gateway API Controller watches for. Getting it wrong is not an error: the class is created, no controller claims it, and every Gateway using it stays unaddressed"

  validation {
    condition     = can(regex("^[a-z0-9.-]+/[a-z0-9.-]+$", var.controller_name))
    error_message = "controller_name must look like a controller name, e.g. application-networking.k8s.aws/gateway-api-controller."
  }
}
variable "listener_name" {
  type        = string
  default     = "http"
  description = "Name of the Gateway's listener, http as the _monolithic template had it. An HTTPRoute's parentRefs.sectionName names this, so the two have to agree - a route naming a listener that does not exist is accepted and never attached"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.listener_name))
    error_message = "listener_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "listener_port" {
  type        = number
  default     = 80
  description = "Port the listener serves on, 80 as the _monolithic template had it"

  validation {
    condition     = var.listener_port > 0 && var.listener_port <= 65535
    error_message = "listener_port must be a valid TCP port."
  }
}
variable "listener_protocol" {
  type        = string
  default     = "HTTP"
  description = "Protocol of the listener. HTTP as the _monolithic template had it - HTTPS would need a certificate on the Lattice listener, which nothing here provisions"

  validation {
    condition     = contains(["HTTP", "HTTPS"], var.listener_protocol)
    error_message = "listener_protocol must be HTTP or HTTPS."
  }
}
