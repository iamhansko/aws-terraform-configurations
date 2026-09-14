variable "vpc_id" {
  type        = string
  description = "VPC ID where the load balancer's security group and target group are created"

  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must be a valid VPC ID (e.g. vpc-0123456789abcdef0)."
  }
}

variable "subnet_ids" {
  type        = list(string)
  description = "Public subnet IDs the ALB is deployed into"

  validation {
    condition     = length(var.subnet_ids) > 0
    error_message = "subnet_ids must contain at least one subnet ID."
  }
}

variable "listener_port" {
  type        = number
  default     = 80
  description = "Port the ALB listener accepts traffic on"

  validation {
    condition     = var.listener_port > 0 && var.listener_port <= 65535
    error_message = "listener_port must be between 1 and 65535."
  }
}

variable "target_port" {
  type        = number
  default     = 3000
  description = "Port on the target instances the ALB forwards traffic to"

  validation {
    condition     = var.target_port > 0 && var.target_port <= 65535
    error_message = "target_port must be between 1 and 65535."
  }
}

variable "health_check_path" {
  type        = string
  default     = "/"
  description = "Path used by the ALB target group health check"

  validation {
    condition     = can(regex("^/", var.health_check_path))
    error_message = "health_check_path must be an absolute path starting with '/'."
  }
}
