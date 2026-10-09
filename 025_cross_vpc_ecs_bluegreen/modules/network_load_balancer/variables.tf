variable "name" {
  type        = string
  description = "Name of the load balancer. A load balancer name is region-wide within its type, so a second copy of this project in one region collides here with DuplicateLoadBalancerName"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{1,32}$", var.name)) && !startswith(var.name, "internal-")
    error_message = "name must be 32 characters or fewer of letters, digits and hyphens, and must not start with \"internal-\", which elbv2 reserves."
  }
}
variable "vpc_id" {
  type        = string
  description = "VPC the load balancer, its security group and its target group belong to"

  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must be a valid VPC ID (e.g. vpc-0123456789abcdef0)."
  }
}
variable "subnet_ids" {
  type        = list(string)
  description = "Subnets the load balancer places its nodes in: public subnets for an internet-facing scheme, private ones for internal"

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "subnet_ids must contain at least two subnets: elbv2 requires two availability zones and rejects a single-zone set at CreateLoadBalancer."
  }
  validation {
    condition     = alltrue([for id in var.subnet_ids : can(regex("^subnet-[0-9a-f]+$", id))])
    error_message = "subnet_ids must contain valid subnet IDs (e.g. subnet-0123456789abcdef0)."
  }
}
variable "internal" {
  type        = bool
  description = "Whether the load balancer is internal. The hub instance is internet-facing and the app instance is internal, and the scheme has to agree with the subnets passed above - an internet-facing scheme in a subnet with no route to an internet gateway is created and then unreachable"
}
variable "listener_port" {
  type        = number
  description = "TCP port the listener accepts on, and the port opened in the security group"

  validation {
    condition     = var.listener_port > 0 && var.listener_port <= 65535
    error_message = "listener_port must be a valid TCP port."
  }
}
variable "target_group_name" {
  type        = string
  description = "Name of the target group"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{1,32}$", var.target_group_name))
    error_message = "target_group_name must be 32 characters or fewer of letters, digits and hyphens."
  }
}
variable "target_port" {
  type        = number
  description = "Port traffic is forwarded to on the target"

  validation {
    condition     = var.target_port > 0 && var.target_port <= 65535
    error_message = "target_port must be a valid TCP port."
  }
}
variable "target_type" {
  type        = string
  description = "Target type. ip for the hub load balancer, whose targets are the other VPC's load balancer addresses registered by the workbench; alb for the app load balancer, whose single target is the internal application load balancer"

  validation {
    condition     = contains(["instance", "ip", "alb"], var.target_type)
    error_message = "target_type must be instance, ip or alb - lambda is not valid for a network load balancer."
  }
}
variable "health_check_protocol" {
  type        = string
  description = "Health check protocol. Must be HTTP or HTTPS when target_type is alb: elbv2 rejects a TCP health check on an alb target group, and the provider otherwise defaults this to the target group protocol, which is TCP. See the health_check block in main.tf"

  validation {
    condition     = contains(["TCP", "HTTP", "HTTPS"], var.health_check_protocol)
    error_message = "health_check_protocol must be TCP, HTTP or HTTPS."
  }
  validation {
    condition     = var.target_type != "alb" || contains(["HTTP", "HTTPS"], var.health_check_protocol)
    error_message = "health_check_protocol must be HTTP or HTTPS when target_type is alb, because a TCP health check cannot evaluate a path and elbv2 refuses the combination at CreateTargetGroup. Set it to HTTP and give health_check_path a path the application load balancer answers."
  }
}
variable "health_check_path" {
  type        = string
  default     = null
  description = "Path the health check requests. Null for a TCP health check, where a path has no meaning and setting one is rejected"

  validation {
    condition     = var.health_check_path == null || can(regex("^/", var.health_check_path))
    error_message = "health_check_path must start with '/', or be null for a TCP health check."
  }
  validation {
    condition     = var.health_check_protocol == "TCP" || var.health_check_path != null
    error_message = "health_check_path is required when health_check_protocol is HTTP or HTTPS: without it the check requests / and a target that only answers a health path reports unhealthy."
  }
}
variable "health_check_port" {
  type        = string
  description = "Port the health check uses. traffic-port follows target_port, which is what both instances want here"

  validation {
    condition     = var.health_check_port == "traffic-port" || can(regex("^[0-9]+$", var.health_check_port))
    error_message = "health_check_port must be \"traffic-port\" or a port number as a string."
  }
}
variable "health_check_interval" {
  type        = number
  description = "Seconds between health checks"

  validation {
    condition     = var.health_check_interval >= 5 && var.health_check_interval <= 300
    error_message = "health_check_interval must be between 5 and 300 seconds."
  }
}
variable "health_check_healthy_threshold" {
  type        = number
  description = "Consecutive successes before a target is considered healthy"

  validation {
    condition     = var.health_check_healthy_threshold >= 2 && var.health_check_healthy_threshold <= 10
    error_message = "health_check_healthy_threshold must be between 2 and 10."
  }
}
variable "health_check_unhealthy_threshold" {
  type        = number
  description = "Consecutive failures before a target is considered unhealthy"

  validation {
    condition     = var.health_check_unhealthy_threshold >= 2 && var.health_check_unhealthy_threshold <= 10
    error_message = "health_check_unhealthy_threshold must be between 2 and 10."
  }
}
variable "deregistration_delay" {
  type        = number
  description = "Seconds the target group waits before completing a deregistration. The _monolithic template set 30; the elbv2 default is 300, which a blue/green switch and a destroy both wait out per target"

  validation {
    condition     = var.deregistration_delay >= 0 && var.deregistration_delay <= 3600
    error_message = "deregistration_delay must be between 0 and 3600 seconds."
  }
}
variable "enable_cross_zone_load_balancing" {
  type        = bool
  description = "Whether a load balancer node may send traffic to targets in another zone. Off by default on a network load balancer, which matters for the hub instance: its targets are addresses in the other VPC registered with AvailabilityZone=all, and without this a node in a zone with no such target has nothing to forward to"
}
variable "ingress_cidr_blocks" {
  type        = list(string)
  default     = []
  description = "Source ranges allowed inbound on listener_port. Configuration literals, so toset() is safe for the for_each over them (rules.md B-8)"

  validation {
    condition     = alltrue([for cidr in var.ingress_cidr_blocks : can(cidrhost(cidr, 0))])
    error_message = "ingress_cidr_blocks must contain valid IPv4 CIDR blocks."
  }
}
variable "ingress_source_security_groups" {
  type        = map(string)
  default     = {}
  description = "Security groups allowed inbound on listener_port, keyed by a caller-chosen label. A map rather than a list because these IDs are another module's output and unknown until apply, and for_each needs statically known keys (rules.md B-8)"

  validation {
    condition     = alltrue([for label in keys(var.ingress_source_security_groups) : can(regex("^[a-zA-Z0-9._-]+$", label))])
    error_message = "ingress_source_security_groups keys land in the rule descriptions, so each must be a non-empty string of letters, digits, dots, underscores or hyphens - the security group description charset excludes an apostrophe (rules.md F-1)."
  }
  validation {
    condition     = alltrue([for id in values(var.ingress_source_security_groups) : can(regex("^sg-[0-9a-f]+$", id))])
    error_message = "ingress_source_security_groups must contain valid security group IDs (e.g. sg-0123456789abcdef0)."
  }
}
variable "all_traffic_source_security_groups" {
  type        = map(string)
  default     = {}
  description = "Security groups allowed inbound on every protocol and port, keyed by a caller-chosen label. This is where the root passes each VPC default security group, reproducing the _monolithic template - nothing in this project is attached to those groups, so the rules are inert"

  validation {
    condition     = alltrue([for label in keys(var.all_traffic_source_security_groups) : can(regex("^[a-zA-Z0-9._-]+$", label))])
    error_message = "all_traffic_source_security_groups keys land in the rule descriptions, so each must be a non-empty string of letters, digits, dots, underscores or hyphens."
  }
  validation {
    condition     = alltrue([for id in values(var.all_traffic_source_security_groups) : can(regex("^sg-[0-9a-f]+$", id))])
    error_message = "all_traffic_source_security_groups must contain valid security group IDs (e.g. sg-0123456789abcdef0)."
  }
}
variable "security_group_name" {
  type        = string
  description = "Name of the load balancer security group"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.security_group_name)) && !startswith(var.security_group_name, "sg-")
    error_message = "security_group_name must be 1-255 characters from the set AWS accepts for a security group name (a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*, no apostrophe) and must not start with \"sg-\", which EC2 reserves for security group IDs."
  }
}
variable "security_group_description" {
  type        = string
  description = "Description of the load balancer security group"

  validation {
    condition     = length(var.security_group_description) > 0
    error_message = "security_group_description must not be empty."
  }
  validation {
    # rules.md F-1, and the cost of getting it wrong is higher here than elsewhere: description
    # forces a new security group, and a network load balancer cannot have its groups changed
    # after creation, so the load balancer is replaced with it.
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.security_group_description))
    error_message = "security_group_description must be 1-255 characters from the set AWS accepts for a security group description: a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*. An apostrophe is NOT allowed - EC2 rejects the CreateSecurityGroup call with InvalidParameterValue, which otherwise only surfaces at apply time."
  }
}
