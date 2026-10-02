variable "chart_version" {
  type        = string
  default     = "1.30.5"
  description = "Version of the istio base, istiod and gateway charts. All three are released together from the same repository and are meant to be installed at the same version - istiod reads the CRDs base installs, and the gateway's injected proxy is the same build as the control plane. Pinned rather than floating, so a re-apply months later installs the same mesh"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.chart_version))
    error_message = "chart_version must be a semantic version (e.g. 1.30.5)."
  }
}
variable "chart_repository" {
  type        = string
  default     = "https://istio-release.storage.googleapis.com/charts"
  description = "Helm repository hosting the istio charts"

  validation {
    condition     = can(regex("^(https://|oci://)", var.chart_repository))
    error_message = "chart_repository must be an https:// or oci:// URL."
  }
}
variable "control_plane_namespace" {
  type        = string
  default     = "istio-system"
  description = "Namespace the base and istiod charts install into. istio-system is not merely conventional: istiod's webhooks and the mesh ConfigMap are looked up there by name"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.control_plane_namespace))
    error_message = "control_plane_namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "gateway_namespace" {
  type        = string
  default     = "istio-ingress"
  description = "Namespace the ingress gateway installs into. A namespace of its own rather than istio-system, which is what Istio recommends: the gateway is data plane, and keeping it separate means its RBAC and any namespace-scoped policy do not also apply to the control plane"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.gateway_namespace))
    error_message = "gateway_namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "gateway_release_name" {
  type        = string
  default     = "istio-ingressgateway"
  description = "Helm release name for the gateway chart. The chart names the Service after the release, so this is also the second half of the adoption stack tag the pre-created load balancer must carry - change it and the controller builds its own load balancer instead of adopting that one (rules.md G-3)"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.gateway_release_name))
    error_message = "gateway_release_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "service_ports" {
  type = map(number)
  default = {
    http2 = 80
  }
  description = "Ports the gateway Service publishes, keyed by port name. This replaces the chart's default list rather than adding to it, which drops the chart's 15021 and 443 entries on purpose: each published port becomes a load balancer listener, and a listener whose port the frontend security group does not open accepts nothing while every Terraform resource still reports success (rules.md G-1). 443 is also pointless without a certificate, and 15021 is the readiness endpoint, which the health check below reaches directly on the pod rather than through a public listener"

  validation {
    condition     = length(var.service_ports) > 0
    error_message = "service_ports must contain at least one port; a gateway that publishes nothing gets a load balancer with no listeners."
  }
  validation {
    condition     = alltrue([for name in keys(var.service_ports) : can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", name)) && length(name) <= 15])
    error_message = "service_ports keys are Kubernetes port names, so each must be a lowercase RFC 1123 DNS label of 15 characters or fewer."
  }
  validation {
    condition     = alltrue([for port in values(var.service_ports) : port > 0 && port <= 65535])
    error_message = "service_ports values must be valid TCP ports."
  }
}
variable "scheme" {
  type        = string
  default     = "internet-facing"
  description = "Load balancer scheme the gateway Service asks for. Must agree with the internal flag on the pre-created load balancer, because the controller treats a mismatch as a different load balancer and builds a second one rather than reporting an error (rules.md G-3)"

  validation {
    condition     = contains(["internet-facing", "internal"], var.scheme)
    error_message = "scheme must be either internet-facing or internal."
  }
}
variable "nlb_target_type" {
  type        = string
  default     = "ip"
  description = "Whether the load balancer sends traffic to pod addresses (ip) or to node ports (instance). ip, so traffic arrives on the gateway pod's own port and the security group rule that admits it can name that exact port. With instance the port is a NodePort Kubernetes picks at random from 30000-32767, which Terraform cannot know, leaving no way to write a rule narrower than the whole range (rules.md G-1/G-2). Note the annotation name carries an nlb- prefix that the Ingress equivalent does not"

  validation {
    condition     = contains(["ip", "instance"], var.nlb_target_type)
    error_message = "nlb_target_type must be either ip or instance."
  }
}
variable "frontend_security_group_ids" {
  type        = list(string)
  default     = []
  description = "Security groups the controller should attach to the load balancer, named by ID in the Service annotation. Passed so the same groups Terraform attached to the pre-created load balancer are the ones the controller intends to keep - the controller reconciles the load balancer's groups towards what this annotation says, so a group attached by Terraform and absent here is removed. When empty the annotation is omitted and the controller manages the groups itself (rules.md B-6)"

  validation {
    condition     = alltrue([for id in var.frontend_security_group_ids : can(regex("^sg-[0-9a-f]+$", id))])
    error_message = "frontend_security_group_ids must contain valid security group IDs (e.g. sg-0123456789abcdef0)."
  }
}
variable "health_check_port" {
  type        = number
  default     = 15021
  description = "Port the load balancer health-checks on the gateway pod. 15021 is the proxy's status port, and checking it rather than the traffic port is not a refinement but a requirement: Envoy only binds a traffic port once a Gateway resource declares a server on it, so a health check against port 80 fails outright on a mesh with no routes configured yet and leaves every target unhealthy. The status port answers from the moment the pod is ready. It is deliberately not in service_ports, so it is reachable on the pod without also becoming a public listener"

  validation {
    condition     = var.health_check_port > 0 && var.health_check_port <= 65535
    error_message = "health_check_port must be a valid TCP port."
  }
}
variable "health_check_path" {
  type        = string
  default     = "/healthz/ready"
  description = "HTTP path the health check requests on health_check_port, which is what the proxy's status port serves readiness on"

  validation {
    condition     = startswith(var.health_check_path, "/")
    error_message = "health_check_path must start with '/'."
  }
}
variable "cross_zone_enabled" {
  type        = bool
  default     = true
  description = "Whether the network load balancer forwards across Availability Zones. On, because gateway pods are not spread evenly over zones and a network load balancer with this off only reaches targets in the zone the client happened to resolve - which presents as intermittent failures rather than an outage"
}
variable "timeout_seconds" {
  type        = number
  default     = 900
  description = "How long each release may take to become ready. All three wait: istiod has to be Available before the gateway chart's injected proxy can get its configuration, and the gateway has to be Available before a load balancer exists to adopt"

  validation {
    condition     = var.timeout_seconds > 0
    error_message = "timeout_seconds must be greater than zero."
  }
}
