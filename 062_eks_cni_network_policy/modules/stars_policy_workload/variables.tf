variable "stars_namespace" {
  type        = string
  default     = "stars"
  description = "Namespace holding the frontend and backend probes. The NetworkPolicy files this module writes for the demo name this namespace, and the probes address each other as <service>.<namespace>, so renaming it changes the URLs the probes are started with"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.stars_namespace))
    error_message = "stars_namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "client_namespace" {
  type        = string
  default     = "client"
  description = "Namespace holding the client probe. Carries the role=client label, which is what the frontend policy's namespaceSelector matches on - a namespace without that label makes the policy match nothing, which reads as the policy having no effect"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.client_namespace))
    error_message = "client_namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "management_ui_namespace" {
  type        = string
  default     = "management-ui"
  description = "Namespace holding the management UI. Carries the role=management-ui label that the allow-ui policies select on, and its name is the first half of the load balancer's adoption stack tag (rules.md G-3)"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.management_ui_namespace))
    error_message = "management_ui_namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "management_ui_name" {
  type        = string
  default     = "management-ui"
  description = "Name of the management UI Service and Deployment. The Service name is the second half of the adoption stack tag, so the pre-created load balancer must be tagged <management_ui_namespace>/<this> or the controller builds its own instead (rules.md G-3)"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.management_ui_name))
    error_message = "management_ui_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "probe_image" {
  type        = string
  default     = "calico/star-probe:v0.1.0"
  description = "Image for the frontend, backend and client probes. Pinned rather than floating, as the upstream eks-workshop manifests pin it"

  validation {
    condition     = length(var.probe_image) > 0 && can(regex(":", var.probe_image))
    error_message = "probe_image must include an explicit tag, so an apply months from now runs what was tested."
  }
}
variable "collect_image" {
  type        = string
  default     = "calico/star-collect:v0.1.0"
  description = "Image for the management UI, which collects status from the probes and draws the graph"

  validation {
    condition     = length(var.collect_image) > 0 && can(regex(":", var.collect_image))
    error_message = "collect_image must include an explicit tag."
  }
}
variable "frontend_port" {
  type        = number
  default     = 80
  description = "Port the frontend probe serves on. Reaches the probe twice: as the Service port and inside the --urls argument every probe is started with, so both move together"

  validation {
    condition     = var.frontend_port > 0 && var.frontend_port <= 65535
    error_message = "frontend_port must be between 1 and 65535."
  }
}
variable "backend_port" {
  type        = number
  default     = 6379
  description = "Port the backend probe serves on, and the port the demo's backend NetworkPolicy allows from the frontend"

  validation {
    condition     = var.backend_port > 0 && var.backend_port <= 65535
    error_message = "backend_port must be between 1 and 65535."
  }
}
variable "client_port" {
  type        = number
  default     = 9000
  description = "Port the client probe serves on"

  validation {
    condition     = var.client_port > 0 && var.client_port <= 65535
    error_message = "client_port must be between 1 and 65535."
  }
}
variable "management_ui_container_port" {
  type        = number
  default     = 9001
  description = "Port the management UI container listens on. The Service's targetPort, which with target-type ip is also where the load balancer sends traffic - so this is the port the pod-side security group rule has to open, not the Service port (rules.md G-1)"

  validation {
    condition     = var.management_ui_container_port > 0 && var.management_ui_container_port <= 65535
    error_message = "management_ui_container_port must be between 1 and 65535."
  }
}
variable "management_ui_service_port" {
  type        = number
  default     = 80
  description = "Port the management UI Service publishes, and therefore the load balancer's listener port. The frontend security group has to open this one"

  validation {
    condition     = var.management_ui_service_port > 0 && var.management_ui_service_port <= 65535
    error_message = "management_ui_service_port must be between 1 and 65535."
  }
}
variable "scheme" {
  type        = string
  default     = "internet-facing"
  description = "Load balancer scheme annotated on the management UI Service. Must agree with the subnets the pre-created load balancer sits in and with its internal flag, or the controller builds a second load balancer rather than adopting it (rules.md G-3)"

  validation {
    condition     = contains(["internet-facing", "internal"], var.scheme)
    error_message = "scheme must be internet-facing or internal."
  }
}
variable "nlb_target_type" {
  type        = string
  default     = "ip"
  description = "How the NLB registers targets. ip sends traffic to the pod address directly, which works because the VPC CNI makes pod IPs routable in the VPC (rules.md G-1)"

  validation {
    condition     = contains(["ip", "instance"], var.nlb_target_type)
    error_message = "nlb_target_type must be ip or instance."
  }
}
variable "frontend_security_group_ids" {
  type        = list(string)
  description = "Security groups the controller keeps on the load balancer, as a list of IDs the caller resolved. The module is handed IDs and never learns which is a load balancer group and which is the cluster group (rules.md B-6)"

  validation {
    condition     = length(var.frontend_security_group_ids) > 0
    error_message = "frontend_security_group_ids must contain at least one ID. An NLB cannot be given security groups after creation, so a pre-created one that starts with none can never gain any."
  }
}
variable "apply_network_policies" {
  type        = bool
  default     = true
  description = "Whether the demo's six NetworkPolicy objects are created. True, so an apply lands the demo in its finished state: the management UI reaches every probe, the frontend reaches the backend, the client reaches the frontend, and nothing else connects. Set false to see the unrestricted graph - every arrow green - without deleting objects behind Terraform's back, which the next apply would simply put back (rules.md B-4). Independent of whether the policies are enforced: that is enableNetworkPolicy on the vpc-cni addon, and with it off these objects are accepted and ignored (rules.md E-5)"
}
variable "replicas" {
  type        = number
  default     = 1
  description = "Replicas for each probe and for the management UI. One is enough: the demo is about which connections are allowed, not about capacity"

  validation {
    condition     = var.replicas >= 1
    error_message = "replicas must be at least 1."
  }
}
