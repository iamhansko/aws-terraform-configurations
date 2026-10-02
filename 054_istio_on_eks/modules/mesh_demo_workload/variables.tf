variable "namespace" {
  type        = string
  default     = "mesh-demo"
  description = "Namespace for the demo application. Created here with the sidecar injection label, which is what puts the application in the mesh at all"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.namespace)) && length(var.namespace) <= 63
    error_message = "namespace must be a valid lowercase RFC 1123 DNS label of 63 characters or fewer."
  }
  validation {
    # This module creates the namespace, so naming a built-in one would have Terraform
    # adopt an object it did not create and then delete it on destroy, which the API
    # server refuses for default and kube-system.
    condition     = !contains(["default", "kube-system", "kube-public", "kube-node-lease", "istio-system"], var.namespace)
    error_message = "namespace must not be a built-in namespace or istio-system; this module creates the namespace it is given and would delete it on destroy."
  }
}
variable "name" {
  type        = string
  default     = "demo-app"
  description = "Name of the demo Deployment, its Service, and the VirtualService that routes to it"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.name))
    error_message = "name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "injection_label" {
  type = map(string)
  default = {
    "istio-injection" = "enabled"
  }
  description = "Labels applied to the namespace to opt it into sidecar injection. istio-injection=enabled is the revisionless form, which works because the base chart marks its install as the default revision - without that marking this label matches no webhook and the pods come up with no sidecar. A pod with no sidecar is not a failure anywhere: it runs, it serves traffic, it simply is not in the mesh and never appears in Kiali"

  validation {
    condition     = length(var.injection_label) > 0
    error_message = "injection_label must contain at least one label; without it the namespace is not part of the mesh and nothing reports that."
  }
}
variable "image" {
  type        = string
  default     = "public.ecr.aws/nginx/nginx:1.29.5-alpine"
  description = "Container image for the demo application. Pulled from ECR Public rather than Docker Hub, which rate-limits anonymous pulls per source address - and every node here shares one NAT gateway address per zone, so a Docker Hub image is exactly the kind that works once and fails on a re-apply"

  validation {
    condition     = length(var.image) > 0
    error_message = "image must not be empty."
  }
  validation {
    condition     = can(regex(":[a-zA-Z0-9._-]+$", var.image))
    error_message = "image must carry an explicit tag; a floating latest makes a re-apply install something different without any diff in plan."
  }
}
variable "replicas" {
  type        = number
  default     = 2
  description = "How many application pods to run. Two rather than one so the mesh has something to load balance across, which is the difference between a Kiali graph with one edge and one that shows traffic being distributed"

  validation {
    condition     = var.replicas >= 1
    error_message = "replicas must be at least 1."
  }
}
variable "container_port" {
  type        = number
  default     = 80
  description = "Port the application container listens on"

  validation {
    condition     = var.container_port > 0 && var.container_port <= 65535
    error_message = "container_port must be a valid TCP port."
  }
}
variable "service_port" {
  type        = number
  default     = 80
  description = "Port the application's Service publishes. This is a plain ClusterIP Service: the load balancer never talks to it, since traffic reaches the mesh through the ingress gateway and is routed by the VirtualService"

  validation {
    condition     = var.service_port > 0 && var.service_port <= 65535
    error_message = "service_port must be a valid TCP port."
  }
}
variable "service_port_name" {
  type        = string
  default     = "http"
  description = "Name of the Service port. Istio infers a port's protocol from this name, and the inference is the whole reason it is a variable rather than a literal: a port named http gets HTTP routing, metrics and retries, while an unnamed port or one named something Istio does not recognise is treated as opaque TCP - the VirtualService's HTTP rules then match nothing and the request is passed through unrouted"

  validation {
    condition     = can(regex("^(http|http2|https|grpc|grpc-web|tcp|tls|mongo|mysql|redis|udp)(-[a-z0-9-]+)?$", var.service_port_name))
    error_message = "service_port_name must start with a protocol prefix Istio recognises (http, http2, https, grpc, grpc-web, tcp, tls, mongo, mysql, redis, udp), optionally followed by a hyphenated suffix."
  }
}
variable "gateway_selector" {
  type        = map(string)
  description = "Labels selecting the ingress gateway pods this Gateway configures. Passed in from the istio module rather than restated, because a selector that matches nothing is accepted by the API server and programs no listener - the load balancer then has healthy targets and refuses every request (rules.md B-5)"

  validation {
    condition     = length(var.gateway_selector) > 0
    error_message = "gateway_selector must not be empty; an empty selector matches no gateway and silently configures nothing."
  }
}
variable "gateway_port" {
  type        = number
  description = "Port the Gateway declares a server on. Must be a port the gateway Service publishes, and therefore a load balancer listener: a Gateway on a port the Service does not publish configures a listener nothing can reach, and a published port with no Gateway is a listener that refuses connections. Passed in from the istio module so the two cannot drift (rules.md B-5)"

  validation {
    condition     = var.gateway_port > 0 && var.gateway_port <= 65535
    error_message = "gateway_port must be a valid TCP port."
  }
}
variable "hosts" {
  type        = list(string)
  default     = ["*"]
  description = "Host names the Gateway accepts and the VirtualService matches. A wildcard, because the demo is reached through the load balancer's generated AWS DNS name, which is not known when this configuration is written. Narrow it to a real name once one exists - a wildcard Gateway accepts requests for any Host header, including ones meant for other services on the same listener"

  validation {
    condition     = length(var.hosts) > 0
    error_message = "hosts must contain at least one entry."
  }
}
variable "route_traffic" {
  type        = bool
  default     = true
  description = "Whether to create the Gateway and VirtualService that route inbound traffic to the application. True, so an apply produces something the load balancer URL actually serves. Set false to see the state the mesh is in before any routing exists: the gateway pod is Running, the load balancer's targets are healthy - because the health check is against the proxy's status port, not a traffic port - and every request to port 80 is refused, because Envoy only binds a traffic port once a Gateway declares a server on it. That is the single most confusing state to land in by accident, so it is worth being able to reach on purpose (rules.md B-4)"
}
variable "cpu_request" {
  type        = string
  default     = "10m"
  description = "CPU request per application pod. Small, because the node group also has to fit istiod, the gateway proxy, the Kiali operator and the Kiali server"

  validation {
    condition     = can(regex("^[0-9]+m?$", var.cpu_request))
    error_message = "cpu_request must be a Kubernetes CPU quantity such as 10m or 1."
  }
}
variable "memory_request" {
  type        = string
  default     = "32Mi"
  description = "Memory request per application pod, on top of which the injected sidecar adds its own"

  validation {
    condition     = can(regex("^[0-9]+(Ki|Mi|Gi)?$", var.memory_request))
    error_message = "memory_request must be a Kubernetes memory quantity such as 32Mi."
  }
}
