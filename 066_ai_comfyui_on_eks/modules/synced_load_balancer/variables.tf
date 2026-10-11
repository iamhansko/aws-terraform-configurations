variable "cluster_name" {
  type        = string
  description = "Name of the EKS cluster, written into the elbv2.k8s.aws/cluster tag. The controller only considers a load balancer its own when this matches its own cluster name"

  validation {
    condition     = length(var.cluster_name) > 0
    error_message = "cluster_name must not be empty."
  }
}
variable "name" {
  type        = string
  default     = null
  description = "Optional load balancer name. When null, a unique name is generated, which avoids collisions when this project is deployed twice in one account"

  validation {
    condition     = var.name == null || can(regex("^[a-zA-Z0-9-]{1,32}$", var.name))
    error_message = "name must be 32 characters or fewer of letters, digits and hyphens, or null."
  }
}
variable "load_balancer_type" {
  type        = string
  default     = "application"
  description = "Whether to pre-create an ALB (application, provisioned from an Ingress) or an NLB (network, provisioned from a Service of type LoadBalancer). Must match the shape the workload actually asks for, otherwise the controller creates a second load balancer instead of adopting this one"

  validation {
    condition     = contains(["application", "network"], var.load_balancer_type)
    error_message = "load_balancer_type must be either application or network."
  }
}
variable "internal" {
  type        = bool
  default     = false
  description = "Whether the load balancer is internal. Must agree with the workload's scheme annotation, since the controller treats a mismatch as a different load balancer"
}
variable "subnet_ids" {
  type        = list(string)
  description = "Subnets the load balancer's nodes are placed in: public subnets for an internet-facing scheme, private ones for internal"

  validation {
    condition     = length(var.subnet_ids) >= 2 && alltrue([for s in var.subnet_ids : can(regex("^subnet-[0-9a-f]+$", s))])
    error_message = "subnet_ids must contain at least two valid subnet IDs, since Elastic Load Balancing requires two availability zones."
  }
}
variable "security_group_ids" {
  type        = list(string)
  default     = []
  description = "Frontend security groups attached to the load balancer. Network load balancers accept security groups only when assigned at creation time, which is one reason to pre-create the load balancer rather than let the controller do it. When empty, no group is attached"

  validation {
    condition     = alltrue([for id in var.security_group_ids : can(regex("^sg-[0-9a-f]+$", id))])
    error_message = "security_group_ids must contain valid security group IDs (e.g. sg-0123456789abcdef0)."
  }
}
variable "resource_tag_prefix" {
  type        = string
  default     = "ingress"
  description = "Which controller tag namespace to use: 'ingress' for a load balancer provisioned from an Ingress (ingress.k8s.aws/resource, ingress.k8s.aws/stack), 'service' for one provisioned from a Service of type LoadBalancer"

  validation {
    condition     = contains(["ingress", "service"], var.resource_tag_prefix)
    error_message = "resource_tag_prefix must be either ingress or service."
  }
}
variable "stack" {
  type        = string
  description = "The <namespace>/<name> the controller writes into its stack tag: the Ingress for an ALB, the Service for an NLB. Derived once by the caller from the same namespace and name the workload is given, so the two cannot drift (rules.md B-5) - and from a value rather than the workload module's output, so this load balancer can exist before the Ingress does. Taken from an output, it would wait for the Ingress, and the controller would reconcile an Ingress whose load balancer does not exist yet and build its own (rules.md G-3)"

  validation {
    condition     = can(regex("^[a-z0-9-]+/[a-z0-9-]+$", var.stack))
    error_message = "stack must look like <namespace>/<name>."
  }
}
variable "idle_timeout" {
  type        = number
  default     = 60
  description = "ALB idle timeout in seconds. Has to be the same number the workload's alb.ingress.kubernetes.io/load-balancer-attributes annotation asks for: the controller writes that attribute onto the load balancer it adopts, and if Terraform holds a different value every apply puts it back - a tug of war that drops long-lived WebSockets each time (rules.md B-5/E-8). Only meaningful for an application load balancer"

  validation {
    condition     = var.idle_timeout >= 1 && var.idle_timeout <= 4000
    error_message = "idle_timeout must be between 1 and 4000 seconds, the range ELB accepts."
  }
}
variable "enable_deletion_protection" {
  type        = bool
  default     = false
  description = "Whether to block deletion of the load balancer. False so terraform destroy can tear the demo down"
}
variable "additional_tags" {
  type        = map(string)
  default     = {}
  description = "Extra tags merged onto the load balancer, on top of the three the controller matches on"

  validation {
    condition     = alltrue([for key in keys(var.additional_tags) : length(key) > 0])
    error_message = "additional_tags must not contain empty AWS tag keys."
  }
}
