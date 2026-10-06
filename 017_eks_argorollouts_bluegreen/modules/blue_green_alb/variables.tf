variable "name" {
  type        = string
  default     = "alb"
  description = "Name of the Application Load Balancer, as the _monolithic template's 'aws elbv2 create-load-balancer --name alb' had it"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{1,32}$", var.name)) && !startswith(var.name, "internal-")
    error_message = "name must be 32 characters or fewer of letters, digits and hyphens, and must not start with \"internal-\", which Elastic Load Balancing reserves."
  }
}
variable "target_group_name" {
  type        = string
  default     = "active-tg"
  description = "Name of the target group the Rollout's activeService points at. 'active' because a blue/green Rollout keeps a second, preview target group alongside it"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{1,32}$", var.target_group_name))
    error_message = "target_group_name must be 32 characters or fewer of letters, digits and hyphens."
  }
}
variable "vpc_id" {
  type        = string
  description = "VPC the target group registers pod IPs in"

  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must be a valid VPC ID (e.g. vpc-0123456789abcdef0)."
  }
}
variable "subnet_ids" {
  type        = list(string)
  description = "Subnets the load balancer's nodes sit in. The _monolithic template used the private subnets, which is why the demo is reached through CloudFront and the bastion rather than directly"

  validation {
    condition     = length(var.subnet_ids) >= 2 && alltrue([for s in var.subnet_ids : can(regex("^subnet-[0-9a-f]+$", s))])
    error_message = "subnet_ids must contain at least two valid subnet IDs, since Elastic Load Balancing requires two availability zones."
  }
}
variable "security_group_ids" {
  type        = list(string)
  description = "Security groups attached to the load balancer. The _monolithic template attached the EKS cluster security group, which is what lets the load balancer reach pod IPs"

  validation {
    condition     = length(var.security_group_ids) > 0 && alltrue([for id in var.security_group_ids : can(regex("^sg-[0-9a-f]+$", id))])
    error_message = "security_group_ids must contain at least one valid security group ID."
  }
}
variable "internal" {
  type        = bool
  default     = true
  description = "Whether the load balancer is internal. True because it lives in the private subnets, matching the _monolithic template - an internet-facing scheme there would have no route in"

  validation {
    condition     = var.internal
    error_message = "internal must be true in this configuration. subnet_ids are the private subnets, and Elastic Load Balancing rejects an internet-facing load balancer whose subnets have no route to an internet gateway."
  }
}
variable "port" {
  type        = number
  default     = 80
  description = "Listener port, and the port the target group forwards to. Both are 80 because target_type is ip and the pods listen on 80"

  validation {
    condition     = var.port > 0 && var.port <= 65535
    error_message = "port must be a valid TCP port."
  }
}
variable "health_check_path" {
  type        = string
  default     = "/"
  description = "Path the target group health check requests"

  validation {
    condition     = can(regex("^/", var.health_check_path))
    error_message = "health_check_path must start with '/'."
  }
}
variable "health_check_matcher" {
  type        = string
  default     = "200"
  description = "HTTP status codes counted as healthy"

  validation {
    condition     = can(regex("^[0-9,-]+$", var.health_check_matcher))
    error_message = "health_check_matcher must be a status code, a comma-separated list, or a range (e.g. 200, 200,202, 200-299)."
  }
}
variable "health_check_interval_seconds" {
  type        = number
  default     = 15
  description = "Seconds between health checks. Shorter than the 30-second default so a blue/green promotion turns the new target group healthy quickly enough to watch"

  validation {
    condition     = var.health_check_interval_seconds >= 5 && var.health_check_interval_seconds <= 300
    error_message = "health_check_interval_seconds must be between 5 and 300."
  }
}
variable "health_check_healthy_threshold" {
  type        = number
  default     = 2
  description = "Consecutive successes before a target counts as healthy"

  validation {
    condition     = var.health_check_healthy_threshold >= 2 && var.health_check_healthy_threshold <= 10
    error_message = "health_check_healthy_threshold must be between 2 and 10."
  }
}
variable "health_check_unhealthy_threshold" {
  type        = number
  default     = 2
  description = "Consecutive failures before a target counts as unhealthy"

  validation {
    condition     = var.health_check_unhealthy_threshold >= 2 && var.health_check_unhealthy_threshold <= 10
    error_message = "health_check_unhealthy_threshold must be between 2 and 10."
  }
}
