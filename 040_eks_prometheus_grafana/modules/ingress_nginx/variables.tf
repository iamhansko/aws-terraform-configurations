variable "release_name" {
  type        = string
  description = "Helm release name. The chart derives the controller Service name from it as <release_name>-ingress-nginx-controller, which is also the second half of the stack tag a pre-created load balancer must carry to be adopted (rules.md G-3), so this value reaches AWS as configuration"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.release_name))
    error_message = "release_name must be a valid lowercase RFC 1123 DNS label - it becomes part of a Service name."
  }
}
variable "namespace" {
  type        = string
  default     = "monitoring"
  description = "Namespace the controller is installed into"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "service_name" {
  type        = string
  description = "Name of the controller Service the chart will create, which is <release_name>-ingress-nginx-controller. Passed in rather than derived here because the caller has to build the matching load balancer stack tag before this release runs, and deriving it in both places is how the two drift apart (rules.md B-5)"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$", var.service_name))
    error_message = "service_name must be a valid lowercase Kubernetes Service name."
  }
}
variable "stack_tag" {
  type        = string
  description = "The <namespace>/<service> value the AWS Load Balancer Controller writes into its service.k8s.aws/stack tag for this Service. Re-exposed as an output so a mismatch with the pre-created load balancer is visible in terraform output rather than only as a second load balancer appearing (rules.md G-3)"

  validation {
    condition     = can(regex("^[a-z0-9-]+/[a-z0-9.-]+$", var.stack_tag))
    error_message = "stack_tag must look like <namespace>/<name>."
  }
}
variable "fullname_override" {
  type        = string
  description = "Value for the chart's fullnameOverride, which fixes the name of every object it creates - the controller Service becomes <this>-controller. Set rather than left to the chart because the caller has to know that Service name in advance: it is the second half of the load balancer's adoption stack tag (rules.md G-3). The chart's own helper is not a plain prefix - it collapses the chart name when the release name already contains it - so predicting the name instead of pinning it gets the tag wrong and the controller silently builds a second load balancer"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.fullname_override)) && length(var.fullname_override) <= 53
    error_message = "fullname_override must be a valid lowercase RFC 1123 DNS label of 53 characters or fewer, leaving room for the chart's own suffixes within the 63 character limit."
  }
}
variable "create_namespace" {
  type        = bool
  default     = false
  description = "Whether this release creates the namespace. False by default because several releases share one namespace here, and only one of them can own it"
}
variable "ingress_class_name" {
  type        = string
  description = "Name of the IngressClass this controller owns. Each release needs its own, because an Ingress selects its controller by class and the point of running three of them is to put three different applications behind three different load balancers"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.ingress_class_name))
    error_message = "ingress_class_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "ingress_class_controller_value" {
  type        = string
  description = "The controller identifier written into the IngressClass. Must be unique per release: two IngressClasses sharing a controller value make both controllers reconcile both classes, and each then fights the other over the same Ingress status"

  validation {
    condition     = can(regex("^[a-z0-9.-]+/[a-z0-9./-]+$", var.ingress_class_controller_value))
    error_message = "ingress_class_controller_value must look like a controller name, e.g. ingress.nginx/grafana."
  }
}
variable "chart_version" {
  type        = string
  default     = "4.13.0"
  description = "Pinned ingress-nginx chart version. Pinned rather than floating so an apply months from now installs what was tested"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.chart_version))
    error_message = "chart_version must be a semantic version, e.g. 4.13.0."
  }
}
variable "chart_repository" {
  type        = string
  default     = "https://kubernetes.github.io/ingress-nginx"
  description = "Helm repository holding the ingress-nginx chart"

  validation {
    condition     = can(regex("^https://", var.chart_repository))
    error_message = "chart_repository must be an https URL."
  }
}
variable "scheme" {
  type        = string
  default     = "internet-facing"
  description = "Load balancer scheme. Must agree with the subnets the pre-created load balancer sits in and with its internal flag, or the controller builds a second load balancer rather than adopting that one (rules.md G-3)"

  validation {
    condition     = contains(["internet-facing", "internal"], var.scheme)
    error_message = "scheme must be internet-facing or internal."
  }
}
variable "nlb_target_type" {
  type        = string
  default     = "ip"
  description = "How the NLB registers targets. ip sends traffic to pod addresses directly, which works because the VPC CNI makes pod IPs routable in the VPC and which preserves the client source address without proxy protocol (rules.md G-1)"

  validation {
    condition     = contains(["ip", "instance"], var.nlb_target_type)
    error_message = "nlb_target_type must be ip or instance."
  }
}
variable "frontend_security_group_ids" {
  type        = list(string)
  description = "Security groups the controller keeps on the load balancer. Passed as a list of IDs the caller resolved, so this module never learns which of them is a load balancer group and which is the cluster group (rules.md B-6)"

  validation {
    condition     = length(var.frontend_security_group_ids) > 0
    error_message = "frontend_security_group_ids must contain at least one ID. An NLB cannot have security groups added after creation, so a pre-created one that starts with none can never gain any."
  }
}
variable "service_port" {
  type        = number
  default     = 80
  description = "Port the controller Service publishes"

  validation {
    condition     = var.service_port > 0 && var.service_port <= 65535
    error_message = "service_port must be between 1 and 65535."
  }
}
variable "replica_count" {
  type        = number
  default     = 1
  description = "Controller replicas. One per release is enough for a demo, and three releases already mean three controller pods"

  validation {
    condition     = var.replica_count >= 1
    error_message = "replica_count must be at least 1."
  }
}
variable "timeout_seconds" {
  type        = number
  default     = 600
  description = "How long to wait for the release to become ready. Generous because the Service has to get an address from the load balancer controller before the release settles"

  validation {
    condition     = var.timeout_seconds > 0
    error_message = "timeout_seconds must be positive."
  }
}
variable "additional_set_values" {
  type = list(object({
    name  = string
    value = string
    type  = optional(string)
  }))
  default     = []
  description = "Extra chart values. type is auto when omitted and may only be auto or string, so a caller can force a value the chart must receive as a string (rules.md E-7)"

  validation {
    condition     = alltrue([for v in var.additional_set_values : v.type == null || contains(["auto", "string"], v.type)])
    error_message = "additional_set_values type must be omitted, \"auto\" or \"string\" - the only values helm_release accepts."
  }
}
