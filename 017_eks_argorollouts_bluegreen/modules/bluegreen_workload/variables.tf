variable "namespace" {
  type        = string
  default     = "bluegreen"
  description = "Namespace the Rollout and its two Services live in, as the _monolithic template's 02_bluegreen_rollouts.yaml had it"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "create_namespace" {
  type        = bool
  default     = true
  description = "Whether this module creates the namespace. Set false when pointing at an existing one"
}
variable "rollout_name" {
  type        = string
  default     = "bluegreen-rollout"
  description = "Name of the Rollout object. This is the name 'kubectl argo rollouts get rollout' takes"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.rollout_name))
    error_message = "rollout_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "app_label" {
  type        = string
  default     = "bluegreen"
  description = "Value of the app label tying the Rollout's pod template to both Services. Argo Rollouts adds a pod-template-hash selector on top of this, which is how it points a Service at one version or the other"

  validation {
    condition     = can(regex("^[a-zA-Z0-9]([-._a-zA-Z0-9]*[a-zA-Z0-9])?$", var.app_label))
    error_message = "app_label must be a valid Kubernetes label value."
  }
}
variable "active_service_name" {
  type        = string
  default     = "active-service"
  description = "Service the Rollout keeps pointed at the version currently serving traffic. The TargetGroupBinding below attaches this one to the load balancer's target group"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.active_service_name))
    error_message = "active_service_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "preview_service_name" {
  type        = string
  default     = "preview-service"
  description = "Service the Rollout points at the new version before promotion. Reaching it is how the new version is checked while the old one still serves users"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.preview_service_name))
    error_message = "preview_service_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "active_target_group_arn" {
  type        = string
  description = "ARN of the target group the active Service is bound to. Pass the load balancer module's output rather than restating it - the _monolithic template sed-substituted this ARN into a YAML file, which left nothing connecting the two (rules.md B-5)"

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:elasticloadbalancing:.*:targetgroup/", var.active_target_group_arn))
    error_message = "active_target_group_arn must be an Elastic Load Balancing target group ARN."
  }
}
variable "image" {
  type        = string
  default     = "public.ecr.aws/docker/library/nginx:1.27"
  description = "Container image for the first version. Changing this and applying is what starts a blue/green rollout, so a tag rather than a floating 'latest' is what makes the change visible"

  validation {
    condition     = length(var.image) > 0
    error_message = "image must not be empty."
  }
}
variable "replica_count" {
  type        = number
  default     = 3
  description = "Replicas per version. More than one makes the target group's membership change visible during a promotion"

  validation {
    condition     = var.replica_count > 0
    error_message = "replica_count must be greater than zero."
  }
}
variable "container_port" {
  type        = number
  default     = 80
  description = "Port the container listens on, and both Services' targetPort"

  validation {
    condition     = var.container_port > 0 && var.container_port <= 65535
    error_message = "container_port must be a valid TCP port."
  }
}
variable "service_port" {
  type        = number
  default     = 80
  description = "Port both Services expose, and the port the TargetGroupBinding references"

  validation {
    condition     = var.service_port > 0 && var.service_port <= 65535
    error_message = "service_port must be a valid TCP port."
  }
}
variable "auto_promotion_enabled" {
  type        = bool
  default     = false
  description = "Whether the Rollout promotes the preview version automatically once it is healthy. False so the rollout pauses and waits for 'kubectl argo rollouts promote' - with it true the promotion is over before anyone can watch it, which is the thing this project exists to show"
}
