variable "cluster_name" {
  type        = string
  description = "Cluster the Pod Identity association is created on"

  validation {
    condition     = length(var.cluster_name) > 0
    error_message = "cluster_name must not be empty."
  }
}

variable "image" {
  type        = string
  description = "Image the Deployment runs, taken from the module that built and pushed it so the tag is written once (rules.md B-5)"

  validation {
    condition     = length(var.image) > 0
    error_message = "image must not be empty."
  }
}

variable "name" {
  type        = string
  default     = "eks-mcp-server"
  description = "Name of the Deployment and the value of its app label"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.name))
    error_message = "name must be a valid lowercase RFC 1123 label."
  }
}

variable "namespace" {
  type        = string
  default     = "default"
  description = "Namespace everything here is created in, as the _monolithic template placed it. Also half of the Ingress stack tag a pre-created load balancer has to carry (rules.md G-3)"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a valid lowercase RFC 1123 label."
  }
}

variable "service_account_name" {
  type        = string
  default     = "eks-mcp-server"
  description = "Service account the pod runs as, and the account the Pod Identity association binds to the role. One value on both sides, so the binding cannot miss (rules.md B-5)"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$", var.service_account_name))
    error_message = "service_account_name must be a valid lowercase RFC 1123 subdomain."
  }
}

variable "service_name" {
  type        = string
  default     = "mcp"
  description = "Name of the Service, as the _monolithic template named it. Also the Ingress backend name"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.service_name))
    error_message = "service_name must be a valid lowercase RFC 1123 label."
  }
}

variable "ingress_name" {
  type        = string
  default     = "mcp"
  description = "Name of the Ingress. Together with the namespace this is the ingress.k8s.aws/stack tag value the AWS Load Balancer Controller writes, which is what a pre-created load balancer has to match to be adopted (rules.md G-3)"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.ingress_name))
    error_message = "ingress_name must be a valid lowercase RFC 1123 label."
  }
}

variable "ingress_class_name" {
  type        = string
  default     = "alb"
  description = "IngressClass the Ingress asks for. Without it no controller claims it, which is not an error - the Ingress simply never gets an address (rules.md G-1)"

  validation {
    condition     = length(var.ingress_class_name) > 0
    error_message = "ingress_class_name must not be empty."
  }
}

variable "ingress_annotations" {
  type        = map(string)
  description = "Annotations the AWS Load Balancer Controller reads: scheme, target type, the frontend security groups, the health check path, and the certificate when the caller has one. Supplied by the caller because every value in them comes from another module (rules.md B-6/G-1)"

  validation {
    condition     = alltrue([for key in keys(var.ingress_annotations) : length(key) > 0])
    error_message = "ingress_annotations keys must not be empty."
  }
}

variable "container_port" {
  type        = number
  default     = 8000
  description = "Port the proxy listens on. One value reaching the container port, the probes, the Service, the Ingress backend and the health check annotation, so none of the five can disagree (rules.md B-5)"

  validation {
    condition     = var.container_port > 0 && var.container_port <= 65535
    error_message = "container_port must be a valid TCP port."
  }
}

variable "health_check_path" {
  type        = string
  default     = "/status"
  description = "Path both probes and the ALB health check use. mcp-proxy serves it; the MCP endpoint itself is /mcp and needs a session, so pointing a health check at it reports unhealthy on a working server"

  validation {
    condition     = startswith(var.health_check_path, "/")
    error_message = "health_check_path must start with '/'."
  }
}

variable "replicas" {
  type        = number
  default     = 1
  description = "Replica count. One, as the _monolithic template had it - mcp-proxy keeps per-session state, so a second replica behind one ALB would answer requests for sessions it does not have"

  validation {
    condition     = var.replicas >= 1
    error_message = "replicas must be at least 1."
  }
}

variable "image_pull_policy" {
  type        = string
  default     = "Always"
  description = "Image pull policy. Always, as the _monolithic template set it, and correct for a mutable :latest tag - otherwise a restarted pod keeps whatever the node cached and a rebuilt image never rolls out"

  validation {
    condition     = contains(["Always", "IfNotPresent", "Never"], var.image_pull_policy)
    error_message = "image_pull_policy must be one of: Always, IfNotPresent, Never."
  }
}

variable "iam_policy_arns" {
  type        = list(string)
  default     = []
  description = <<-DESC
    Managed policies attached to the pod's role.

    Empty by default, and that is a deliberate departure from the _monolithic template, which created this
    role with no policy either - but also with an EKS access entry giving it cluster access, and the server
    running with --allow-write and --allow-sensitive-data-access. What the pod can do is decided by that
    access entry (the caller creates it) plus whatever is attached here.

    Anything added here is available to a language model driving the MCP endpoint, so it is worth naming
    the specific permissions rather than reaching for AdministratorAccess (rules.md A-5).
  DESC

  validation {
    condition     = alltrue([for arn in var.iam_policy_arns : can(regex("^arn:aws:iam::", arn))])
    error_message = "iam_policy_arns must contain valid IAM policy ARNs."
  }
}

variable "stack_tag" {
  type        = string
  description = "The <namespace>/<name> value the AWS Load Balancer Controller writes into its ingress.k8s.aws/stack tag for this Ingress. Taken as an input rather than derived here, because the pre-created load balancer has to be tagged with it before this module runs - deriving it from this module's outputs would order the load balancer after the Ingress, which is exactly backwards for adoption (rules.md G-3)"

  validation {
    condition     = can(regex("^[a-z0-9][-a-z0-9.]*/[a-z0-9][-a-z0-9.]*$", var.stack_tag))
    error_message = "stack_tag must look like <namespace>/<ingress-name>."
  }
}
variable "rollout_timeout" {
  type        = string
  default     = "10m"
  description = "How long the apply waits for the Deployment to report an available replica, as a Go duration. Ten minutes covers a cold image pull on a fresh node; past that the rollout is not slow, it is stuck, and the pod's events say why (see the wait_for_rollout note in main.tf for what the provider's error looks like when it is)"

  validation {
    condition     = can(regex("^[0-9]+(s|m|h)$", var.rollout_timeout))
    error_message = "rollout_timeout must be a Go duration such as 10m, 600s or 1h."
  }
}
