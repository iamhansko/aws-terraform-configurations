variable "release_name" {
  type        = string
  description = "Helm release name. This release pins the chart's fullname to it with fullnameOverride, so the controller Service is named <release_name>-controller - which is also the second half of the stack tag a pre-created load balancer must carry to be adopted (rules.md G-3), so this value reaches AWS as configuration"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.release_name))
    error_message = "release_name must be a valid lowercase RFC 1123 DNS label - it becomes part of a Service name."
  }
}
variable "namespace" {
  type        = string
  default     = "kube-system"
  description = "Namespace the controller is installed into, kube-system as the _monolithic template had it. Also the first half of the stack tag a pre-created load balancer must carry (rules.md G-3)"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "service_name" {
  type        = string
  description = "Name of the controller Service the chart will create, which is <release_name>-controller. Passed in rather than derived here because the caller has to build the matching load balancer stack tag before this release runs, and deriving it in both places is how the two drift apart (rules.md B-5)"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$", var.service_name))
    error_message = "service_name must be a valid lowercase Kubernetes Service name."
  }
  # A cross-variable condition, because the constraint is about the pair rather
  # than about either value alone (rules.md B-1). This release sets
  # fullnameOverride to release_name, so the Service the chart creates is exactly
  # <release_name>-controller. Nothing downstream complains when the caller's guess
  # differs: the stack tag on the pre-created load balancer then matches no Service,
  # the controller builds its own, and the only symptom is two load balancers and a
  # dashboard URL pointing at the one without listeners (rules.md G-3). Failing here
  # turns that into a plan-time error.
  validation {
    condition     = var.service_name == "${var.release_name}-controller"
    error_message = "service_name must be \"<release_name>-controller\" - the chart names the controller Service after its fullname, which this release pins to release_name via fullnameOverride. Passing anything else silently breaks load balancer adoption rather than failing (rules.md G-3)."
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
variable "create_namespace" {
  type        = bool
  default     = false
  description = "Whether this release creates the namespace. False by default because several releases share one namespace here, and only one of them can own it"
}
variable "ingress_class_name" {
  type        = string
  description = "Name of the IngressClass this controller owns. No default, because this project runs several releases side by side and two of them claiming the same class name is the mistake worth making impossible - an Ingress naming a class no controller owns is created successfully and then never gets an address, and one naming a class two controllers own is reconciled by both"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.ingress_class_name))
    error_message = "ingress_class_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "ingress_class_controller_value" {
  type        = string
  description = "The controller identifier written into the IngressClass, and what each controller pod matches on to decide which classes are its own. No default for the same reason as ingress_class_name: the chart's default is correct only with a single release, and two IngressClasses sharing a controller value make both controllers reconcile both classes - which produces two load balancers serving the same Ingress and no error anywhere"

  validation {
    condition     = can(regex("^[a-z0-9.-]+/[a-z0-9./-]+$", var.ingress_class_controller_value))
    error_message = "ingress_class_controller_value must look like a controller name, e.g. ingress.nginx/a."
  }
}
variable "set_as_default_ingress_class" {
  type        = bool
  default     = false
  description = "Whether this IngressClass is marked the cluster default. False, because several ingress-nginx releases coexist here and more than one default class makes an Ingress that omits ingressClassName ambiguous. With a single release it is worth turning on, so an Ingress that names no class still gets an address"
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
variable "service_ports" {
  type = map(number)
  default = {
    http  = 80
    https = 443
  }
  description = "Ports the controller Service publishes, keyed by the names the chart defines under controller.service.ports. Both by default, because the chart publishes both whatever is set here and a port the caller's security group does not open becomes a load balancer listener that nothing can reach"

  validation {
    condition     = length(var.service_ports) > 0
    error_message = "service_ports must contain at least one port."
  }
  validation {
    condition     = alltrue([for name in keys(var.service_ports) : contains(["http", "https"], name)])
    error_message = "service_ports keys must be http or https - the only two ports the ingress-nginx chart defines under controller.service.ports. Any other key renders into a value the chart ignores, which is not an error and leaves the Service on its defaults."
  }
  validation {
    condition     = alltrue([for port in values(var.service_ports) : port > 0 && port <= 65535])
    error_message = "service_ports values must be between 1 and 65535."
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
