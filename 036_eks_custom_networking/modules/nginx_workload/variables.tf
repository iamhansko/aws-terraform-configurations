variable "name" {
  type        = string
  default     = "nginx"
  description = "Name shared by the Deployment, Service and Ingress. The Ingress name is the second half of the ALB's adoption stack tag, so this value reaches AWS as a tag (rules.md G-3)"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.name))
    error_message = "name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "namespace" {
  type        = string
  default     = "default"
  description = "Namespace the workload is created in"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "image" {
  type        = string
  default     = "nginxdemos/hello"
  description = "Container image. nginxdemos/hello rather than plain nginx because its page prints the server address, which is what makes custom networking visible in a browser: the address shown comes from the secondary CIDR. Note this is Docker Hub, which rate-limits anonymous pulls - switch to an ECR Public mirror if that bites"

  validation {
    condition     = length(var.image) > 0
    error_message = "image must not be empty."
  }
}
variable "replicas" {
  type        = number
  default     = 2
  description = "Replica count. Two so the demo shows pods in both availability zones, each getting an address from its own zone's pod subnet"

  validation {
    condition     = var.replicas >= 1
    error_message = "replicas must be at least 1."
  }
}
variable "container_port" {
  type        = number
  default     = 80
  description = "Port the container and the Service listen on"

  validation {
    condition     = var.container_port > 0 && var.container_port <= 65535
    error_message = "container_port must be between 1 and 65535."
  }
}
variable "ingress_class_name" {
  type        = string
  default     = "alb"
  description = "IngressClass the Ingress selects. alb is what the AWS Load Balancer Controller registers; without it no controller reconciles the Ingress and nothing happens at all - no error, just an Ingress with no address (rules.md G-1)"

  validation {
    condition     = length(var.ingress_class_name) > 0
    error_message = "ingress_class_name must not be empty."
  }
}
variable "scheme" {
  type        = string
  default     = "internet-facing"
  description = "ALB scheme. Must agree with the pre-created load balancer's internal flag and with the subnets it sits in, or the controller builds a second load balancer rather than adopting that one (rules.md G-3)"

  validation {
    condition     = contains(["internet-facing", "internal"], var.scheme)
    error_message = "scheme must be internet-facing or internal."
  }
}
variable "target_type" {
  type        = string
  default     = "ip"
  description = "How the ALB registers targets. ip, which sends traffic to pod addresses directly - and on this cluster those addresses are in the secondary CIDR, so the ALB reaching them is itself part of what the project demonstrates. instance would need a NodePort Service (rules.md G-1)"

  validation {
    condition     = contains(["ip", "instance"], var.target_type)
    error_message = "target_type must be ip or instance."
  }
}
variable "frontend_security_group_id" {
  type        = string
  description = "Security group the controller keeps on the ALB. Handed over as an ID, so this module never learns where it came from (rules.md B-6)"

  validation {
    condition     = can(regex("^sg-[0-9a-f]+$", var.frontend_security_group_id))
    error_message = "frontend_security_group_id must be a valid security group ID."
  }
}
variable "manage_backend_security_group_rules" {
  type        = bool
  default     = false
  description = "Whether the controller writes the pod-side security group rules itself. True, as the _monolithic template's Ingress had it. With it true the controller needs its backend security group feature enabled, and refuses the combination otherwise - silently, with the reason only in its log (rules.md G-2)"
}
