variable "chart_version" {
  type        = string
  default     = "2.32.0"
  description = "Version of the kiali-operator chart. The operator's version also decides the Kiali server version it installs, so pinning this pins both"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.chart_version))
    error_message = "chart_version must be a semantic version (e.g. 2.32.0)."
  }
}
variable "chart_repository" {
  type        = string
  default     = "https://kiali.org/helm-charts"
  description = "Helm repository hosting the kiali-operator chart"

  validation {
    condition     = can(regex("^(https://|oci://)", var.chart_repository))
    error_message = "chart_repository must be an https:// or oci:// URL."
  }
}
variable "namespace" {
  type        = string
  default     = "istio-system"
  description = "Namespace the operator, the Kiali CR and the Kiali server all live in. istio-system rather than a namespace of its own, because Kiali reads the mesh configuration from there and defaults to looking for it alongside itself"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "name" {
  type        = string
  default     = "kiali"
  description = "Name of the Kiali CR, which is also the name the operator gives the Kiali Deployment and Service, and therefore the Service this module's Ingress routes to. Changing it changes all four at once, which is the reason it is one variable"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.name))
    error_message = "name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "auth_strategy" {
  type        = string
  default     = "anonymous"
  description = "How Kiali authenticates users. anonymous as the _monolithic template had it, which means no login at all: anyone who can reach the load balancer gets full read access to the mesh. Acceptable for a demo behind a security group you control, and the first thing to change for anything else - token requires a service account token, openid delegates to an identity provider"

  validation {
    condition     = contains(["anonymous", "token", "openid", "header"], var.auth_strategy)
    error_message = "auth_strategy must be one of: anonymous, token, openid, header."
  }
}
variable "web_root" {
  type        = string
  default     = "/kiali"
  description = "Path prefix Kiali serves itself under. It has to match the Ingress path, and defaulting it would break the demo: Kiali's own default is /, so a server left at that default receives the /kiali request the load balancer forwards, finds no route for it and answers 404 - an Ingress, target group and pod that are all healthy, serving a page that does not load"

  validation {
    condition     = startswith(var.web_root, "/")
    error_message = "web_root must start with '/'."
  }
  validation {
    condition     = var.web_root == "/" || !endswith(var.web_root, "/")
    error_message = "web_root must not have a trailing slash unless it is exactly \"/\"; Kiali builds its asset URLs by concatenation and a trailing slash produces doubled separators."
  }
}
variable "server_port" {
  type        = number
  default     = 20001
  description = "Port the Kiali server listens on and its Service publishes. With an ALB target type of ip the load balancer sends traffic straight to the pod on this port, so this - not a Service port indirection - is what the pod-side security group rule in the root has to open (rules.md G-1/G-2)"

  validation {
    condition     = var.server_port > 0 && var.server_port <= 65535
    error_message = "server_port must be a valid TCP port."
  }
}
variable "cluster_wide_access" {
  type        = bool
  default     = true
  description = "Whether Kiali may read every namespace rather than a fixed list. True so the mesh graph covers workloads added after the apply; the alternative requires naming namespaces up front and silently omits anything else"
}
variable "istio_namespace" {
  type        = string
  default     = "istio-system"
  description = "Namespace Kiali expects to find the Istio control plane in, which is where it reads the mesh ConfigMap and istiod's registry from. Set explicitly rather than relying on the default being the same as var.namespace, so moving Kiali out of istio-system does not silently break its view of the mesh"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.istio_namespace))
    error_message = "istio_namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "ingress_class_name" {
  type        = string
  default     = "alb"
  description = "IngressClass that decides which controller handles the Ingress. alb is the class the aws-load-balancer-controller chart creates by default. Getting this wrong, or omitting it, is not an error: no controller claims the Ingress, so nothing happens at all and the ADDRESS column stays empty (rules.md G-1)"

  validation {
    condition     = length(var.ingress_class_name) > 0
    error_message = "ingress_class_name must not be empty."
  }
}
variable "scheme" {
  type        = string
  default     = "internet-facing"
  description = "Load balancer scheme the Ingress asks for. Must agree with the internal flag on the pre-created load balancer, or the controller builds a second one rather than adopting it (rules.md G-3)"

  validation {
    condition     = contains(["internet-facing", "internal"], var.scheme)
    error_message = "scheme must be either internet-facing or internal."
  }
}
variable "target_type" {
  type        = string
  default     = "ip"
  description = "Whether the load balancer sends traffic to pod addresses (ip) or node ports (instance). ip keeps the pod-side rule to a single known port; instance would need the whole NodePort range opened, because Kubernetes picks that port and Terraform cannot know it (rules.md G-1/G-2)"

  validation {
    condition     = contains(["ip", "instance"], var.target_type)
    error_message = "target_type must be either ip or instance."
  }
}
variable "frontend_security_group_ids" {
  type        = list(string)
  default     = []
  description = "Security groups the controller should attach to the load balancer, named by ID in the Ingress annotation. The controller reconciles the load balancer's groups towards this list, so a group Terraform attached but that is absent here is removed. When empty the annotation is omitted and the controller manages the groups itself (rules.md B-6)"

  validation {
    condition     = alltrue([for id in var.frontend_security_group_ids : can(regex("^sg-[0-9a-f]+$", id))])
    error_message = "frontend_security_group_ids must contain valid security group IDs (e.g. sg-0123456789abcdef0)."
  }
}
variable "timeout_seconds" {
  type        = number
  default     = 600
  description = "How long the operator release may take to become ready. This waits for the operator only - the Kiali server it then creates comes up asynchronously afterwards, which is why the Ingress may be reconciled once before its backend Service exists"

  validation {
    condition     = var.timeout_seconds > 0
    error_message = "timeout_seconds must be greater than zero."
  }
}
