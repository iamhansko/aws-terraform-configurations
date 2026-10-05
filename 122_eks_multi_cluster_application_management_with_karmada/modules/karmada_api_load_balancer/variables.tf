variable "vpc_id" {
  type        = string
  description = "VPC the target group is created in. Must be the VPC holding the parent cluster's nodes"

  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must be a valid VPC ID (e.g. vpc-0123456789abcdef0)."
  }
}
variable "subnet_ids" {
  type        = list(string)
  description = "Subnets the load balancer's nodes are placed in. Public subnets when internal is false, private ones when it is true"

  validation {
    condition     = length(var.subnet_ids) >= 2 && alltrue([for subnet in var.subnet_ids : can(regex("^subnet-[0-9a-f]+$", subnet))])
    error_message = "subnet_ids must contain at least two valid subnet IDs - an Elastic Load Balancer requires two availability zones."
  }
}
variable "autoscaling_group_name" {
  type        = string
  description = "Auto Scaling group whose instances are registered as targets, which is the parent cluster's node group. A group name rather than instance IDs so that replaced nodes re-register themselves"

  validation {
    condition     = length(var.autoscaling_group_name) > 0
    error_message = "autoscaling_group_name must not be empty."
  }
}
variable "node_security_group_id" {
  type        = string
  description = "Security group attached to the parent cluster's nodes - in practice the EKS cluster security group, which EKS attaches to managed nodes itself. The rule opening the node port is added to it here rather than by the caller, so the port is opened by whatever opened it (rules.md B-6 inverted: the group is injected, the rule belongs with the load balancer that needs it)"

  validation {
    condition     = can(regex("^sg-[0-9a-f]+$", var.node_security_group_id))
    error_message = "node_security_group_id must be a valid security group ID (e.g. sg-0123456789abcdef0)."
  }
}
variable "ingress_cidr_block" {
  type        = string
  description = "Source range allowed to reach the node port. The VPC's CIDR block, because preserve_client_ip is off on the target group and the source is therefore the load balancer's own interfaces"

  validation {
    condition     = can(cidrhost(var.ingress_cidr_block, 0))
    error_message = "ingress_cidr_block must be a valid IPv4 CIDR block."
  }
}
variable "port" {
  type        = number
  default     = 32443
  description = <<-DESC
    Port used for both the load balancer's listener and the Service's nodePort, so that the port in the
    endpoint is the port found on the nodes. 32443 is what the guidance installer's
    karmada-service-loadbalancer Service published, kept so the endpoint reads the same.

    The caller passes this same value to the chart as apiServer.nodePort. They are independent settings that
    this module chooses to keep equal; if they diverge the listener forwards to a port nothing is listening
    on, and the only symptom is every target reported unhealthy.
  DESC

  validation {
    # The nodePort range, because this value is also the Service's nodePort. Outside it, the chart renders a
    # Service the API server rejects - and the failure appears during the Helm install rather than here.
    condition     = var.port >= 30000 && var.port <= 32767
    error_message = "port must be between 30000 and 32767. It is also used as the Karmada API server Service's nodePort, and Kubernetes only allocates node ports from that range."
  }
}
variable "internal" {
  type        = bool
  default     = false
  description = <<-DESC
    Whether the load balancer is reachable only from inside the VPC. False, which is what the guidance
    installer's Service requested with aws-load-balancer-scheme: internet-facing.

    It has to stay false for this configuration to work as written, and the reason is worth stating: the
    kubectl provider that creates the PropagationPolicy and the demo Deployment runs wherever terraform runs,
    which is outside the VPC. With an internal load balancer those two resources cannot be applied at all.

    What that costs: the Karmada API server is reachable from the internet. It is not open - the only
    credential that can do anything is the client certificate in modules/karmada_certificates, and an
    unauthenticated request authenticates as system:anonymous, which has no permissions - but it is exposed,
    and narrowing it is not possible through a Network Load Balancer, which has no security group of its own
    in this configuration. The alternative is rules.md E-9's shape: an internal endpoint with every
    Kubernetes object applied from an instance inside the VPC by an SSM Association, which gives up having
    any of them in Terraform state.
  DESC
}
variable "name" {
  type        = string
  default     = null
  description = "Optional fixed name for the load balancer and its target group. Null generates both from name_prefix, which is what lets this project be deployed twice in one account"

  validation {
    condition     = var.name == null || can(regex("^[a-zA-Z0-9-]{1,32}$", var.name))
    error_message = "name must be 32 characters or fewer of letters, digits and hyphens, or null."
  }
}
variable "name_prefix" {
  type        = string
  default     = "karmada-"
  description = "Prefix for the generated name when name is null. Six characters or fewer, which is what aws_lb_target_group accepts"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{1,6}$", var.name_prefix))
    error_message = "name_prefix must be 1-6 characters of letters, digits and hyphens. aws_lb_target_group rejects anything longer, even though aws_lb accepts up to 32."
  }
}
variable "tag_name" {
  type        = string
  default     = "karmada-lb"
  description = "Name tag on the load balancer and target group. karmada-lb, which is the name the guidance installer gave the load balancer through its aws-load-balancer-name annotation - kept as a tag rather than as the resource name so that two deployments do not collide"

  validation {
    condition     = length(var.tag_name) > 0
    error_message = "tag_name must not be empty."
  }
}
variable "enable_deletion_protection" {
  type        = bool
  default     = false
  description = "Whether AWS refuses to delete the load balancer. Off: this is a demo, and on it would make terraform destroy fail rather than protect anything"
}
variable "health_check_interval_seconds" {
  type        = number
  default     = 10
  description = "Seconds between health checks. Ten rather than the default thirty, because the gap between the chart finishing and the targets passing is time the apply spends waiting before it can reach the API server"

  validation {
    condition     = contains([10, 30], var.health_check_interval_seconds)
    error_message = "health_check_interval_seconds must be 10 or 30. A Network Load Balancer target group accepts no other values."
  }
}
variable "health_check_healthy_threshold" {
  type        = number
  default     = 2
  description = "Consecutive successes before a target is in service"

  validation {
    condition     = var.health_check_healthy_threshold >= 2 && var.health_check_healthy_threshold <= 10
    error_message = "health_check_healthy_threshold must be between 2 and 10."
  }
}
variable "health_check_unhealthy_threshold" {
  type        = number
  default     = 2
  description = "Consecutive failures before a target is taken out of service. Must equal healthy_threshold on a Network Load Balancer target group"

  validation {
    condition     = var.health_check_unhealthy_threshold >= 2 && var.health_check_unhealthy_threshold <= 10
    error_message = "health_check_unhealthy_threshold must be between 2 and 10."
  }
  validation {
    # The pair is the constraint, so it belongs in a cross-variable condition rather than in a note on each
    # one (rules.md B-1). AWS reports the mismatch as a ValidationError during apply.
    condition     = var.health_check_unhealthy_threshold == var.health_check_healthy_threshold
    error_message = "health_check_unhealthy_threshold must equal health_check_healthy_threshold. A Network Load Balancer target group requires the two thresholds to be the same, and AWS rejects the create call rather than adjusting one of them."
  }
}
