variable "namespace" {
  type        = string
  default     = "game-2048"
  description = "Namespace the workload is created in"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "create_namespace" {
  type        = bool
  default     = true
  description = "Whether this module creates the namespace. Set false when pointing at an existing namespace such as default"
}
variable "app_label" {
  type        = string
  default     = "app-2048"
  description = "Value of the app.kubernetes.io/name label tying the Deployment, Service and pod template together"

  validation {
    condition     = can(regex("^[a-zA-Z0-9]([-._a-zA-Z0-9]*[a-zA-Z0-9])?$", var.app_label))
    error_message = "app_label must be a valid Kubernetes label value."
  }
}
variable "deployment_name" {
  type        = string
  default     = "deployment-2048"
  description = "Name of the Deployment"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.deployment_name))
    error_message = "deployment_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "service_name" {
  type        = string
  default     = "service-2048"
  description = "Name of the Service. Also the second half of the load balancer's ingress.k8s.aws/stack or service.k8s.aws/stack tag, which matters when a pre-created load balancer is meant to be adopted"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.service_name))
    error_message = "service_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "ingress_name" {
  type        = string
  default     = "ingress-2048"
  description = "Name of the Ingress created when create_ingress is true. Also the second half of the load balancer's ingress.k8s.aws/stack tag"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.ingress_name))
    error_message = "ingress_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "image" {
  type        = string
  default     = "public.ecr.aws/l6m2t8p7/docker-2048:latest"
  description = "Container image for the workload"

  validation {
    condition     = length(var.image) > 0
    error_message = "image must not be empty."
  }
}
variable "replica_count" {
  type        = number
  default     = 5
  description = "Number of pod replicas. More than one makes load balancer target registration and health checking visible"

  validation {
    condition     = var.replica_count > 0
    error_message = "replica_count must be greater than zero."
  }
}
variable "container_port" {
  type        = number
  default     = 80
  description = "Port the container listens on, and the Service's targetPort"

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
variable "service_type" {
  type        = string
  default     = "NodePort"
  description = "Service type. NodePort or ClusterIP behind an Ingress (the controller provisions an ALB from the Ingress); LoadBalancer without an Ingress (the controller provisions an NLB from the Service itself)"

  validation {
    condition     = contains(["ClusterIP", "NodePort", "LoadBalancer"], var.service_type)
    error_message = "service_type must be one of: ClusterIP, NodePort, LoadBalancer."
  }
}
variable "service_annotations" {
  type        = map(string)
  default     = {}
  description = "Annotations on the Service. With service_type = LoadBalancer these drive the AWS Load Balancer Controller: aws-load-balancer-type = external moves off the in-tree Classic Load Balancer path, and aws-load-balancer-scheme / -nlb-target-type / -security-groups shape the NLB"

  validation {
    condition     = alltrue([for key in keys(var.service_annotations) : length(key) > 0])
    error_message = "service_annotations must not contain empty annotation keys."
  }
}
variable "create_ingress" {
  type        = bool
  default     = true
  description = "Whether to create an Ingress in front of the Service, which is what makes the controller provision an ALB. Leave false for the Service-type-LoadBalancer (NLB) shape"
}
variable "ingress_class_name" {
  type        = string
  default     = "alb"
  description = "ingressClassName on the Ingress, selecting the AWS Load Balancer Controller's IngressClass"

  validation {
    condition     = length(var.ingress_class_name) > 0
    error_message = "ingress_class_name must not be empty."
  }
}
variable "ingress_annotations" {
  type        = map(string)
  default     = {}
  description = "Annotations on the Ingress, driving the ALB the controller creates: alb.ingress.kubernetes.io/scheme (internal or internet-facing), -target-type, -security-groups and -manage-backend-security-group-rules"

  validation {
    condition     = alltrue([for key in keys(var.ingress_annotations) : length(key) > 0])
    error_message = "ingress_annotations must not contain empty annotation keys."
  }
}
variable "ingress_path" {
  type        = string
  default     = "/"
  description = "Path the Ingress rule matches"

  validation {
    condition     = can(regex("^/", var.ingress_path))
    error_message = "ingress_path must start with '/'."
  }
}
variable "ingress_path_type" {
  type        = string
  default     = "Prefix"
  description = "How ingress_path is matched"

  validation {
    condition     = contains(["Exact", "Prefix", "ImplementationSpecific"], var.ingress_path_type)
    error_message = "ingress_path_type must be one of: Exact, Prefix, ImplementationSpecific."
  }
}
