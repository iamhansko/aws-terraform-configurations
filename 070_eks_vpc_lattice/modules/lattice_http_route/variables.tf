variable "name" {
  type        = string
  description = "Name of the HTTPRoute. No default: this module is instantiated once per route, and the name becomes part of the VPC Lattice service the controller creates - so it also ends up in the domain name the route answers on"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.name))
    error_message = "name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "namespace" {
  type        = string
  default     = "default"
  description = "Namespace the route lives in, as the _monolithic template had it. Has to be the Gateway's namespace unless the Gateway's listener allows routes from elsewhere, which the default does not - a route that is not allowed to attach reports NotAllowedByListeners in its status and nowhere else"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "gateway_name" {
  type        = string
  description = "Gateway this route attaches to, named in its parentRefs. Taken from the module that created it rather than restated: a route naming a Gateway that does not exist is accepted by the API server and attached to nothing (rules.md B-5)"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.gateway_name))
    error_message = "gateway_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "listener_name" {
  type        = string
  description = "Listener on that Gateway, named in parentRefs.sectionName. Also taken from the Gateway module: a route naming a listener the Gateway does not have is accepted and never attached (rules.md B-5)"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.listener_name))
    error_message = "listener_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "rules" {
  type = list(object({
    path_prefix = optional(string)
    backends = list(object({
      name   = string
      port   = number
      weight = optional(number)
    }))
  }))
  description = <<-DESC
    The route's rules, in order. Each rule optionally matches a path prefix and lists the backends it
    sends matching requests to.

    The two shapes this project uses are both expressible here, and they demonstrate different things:

      - one rule, no path prefix, one backend with a weight - every request goes to that backend, and
        the weight is what a second weighted backend would be balanced against. This is the
        canary-deployment shape;
      - several rules, each with a path prefix and one backend - requests are routed by path. This is
        the shape that replaces a reverse proxy.

    A backend naming a Service that does not exist, or a port the Service does not publish, leaves the
    route attached and answering 500 rather than failing at apply - which is why the caller reads both
    values off the service modules rather than restating them (rules.md B-5).
  DESC

  validation {
    condition     = length(var.rules) > 0
    error_message = "rules must contain at least one rule. A route with no rules attaches to the Gateway and matches nothing."
  }
  validation {
    condition     = alltrue([for rule in var.rules : length(rule.backends) > 0])
    error_message = "every rule must list at least one backend."
  }
  validation {
    condition     = alltrue([for rule in var.rules : rule.path_prefix == null || can(regex("^/", rule.path_prefix))])
    error_message = "path_prefix must start with '/' when set."
  }
  validation {
    condition = alltrue(flatten([
      for rule in var.rules : [for backend in rule.backends : backend.port > 0 && backend.port <= 65535]
    ]))
    error_message = "every backend port must be between 1 and 65535."
  }
  validation {
    # A weight on one backend of a rule and not on another is accepted by the API server, which then
    # defaults the missing one to 1 - so a rule meant to split 90/10 splits 90/1 instead. Either all or
    # none.
    condition = alltrue([
      for rule in var.rules :
      length([for backend in rule.backends : backend if backend.weight != null]) == 0 ||
      length([for backend in rule.backends : backend if backend.weight != null]) == length(rule.backends)
    ])
    error_message = "within a rule, either every backend carries a weight or none does. Mixing them makes the API server default the missing weights to 1, so the split is not the one intended and nothing reports it."
  }
}
