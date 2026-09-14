variable "aws_region" {
  type        = string
  default     = null
  description = "Target AWS region. Defaults to the provider chain (AWS_REGION)."

  validation {
    condition     = var.aws_region == null || can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "aws_region must be a valid AWS region identifier (e.g. us-east-1) or null."
  }
}

variable "prefix" {
  type        = string
  default     = "alb-asg"
  description = "Resource name prefix"

  validation {
    condition     = length(var.prefix) > 0
    error_message = "prefix must not be empty."
  }
}

variable "key_name" {
  type        = string
  default     = "alb-asg-key"
  description = "Name of the EC2 key pair created for the bastion and ASG instances"

  validation {
    condition     = can(regex("^[ -~]{1,255}$", var.key_name))
    error_message = "key_name must be a non-empty string of printable ASCII characters, 255 characters or fewer."
  }
}

variable "bastion_instance_type" {
  type        = string
  default     = "t3.small"
  description = "EC2 instance type for the bastion EC2 instance"

  validation {
    condition     = can(regex("^[a-z0-9]+\\.[a-z0-9]+$", var.bastion_instance_type))
    error_message = "bastion_instance_type must be a valid EC2 instance type (e.g. t3.small)."
  }
}

variable "app_instance_type" {
  type        = string
  default     = "t3.small"
  description = "EC2 instance type for the ASG instances"

  validation {
    condition     = can(regex("^[a-z0-9]+\\.[a-z0-9]+$", var.app_instance_type))
    error_message = "app_instance_type must be a valid EC2 instance type (e.g. t3.small)."
  }
}

variable "app_min_size" {
  type        = number
  default     = 4
  description = "Minimum number of ASG instances"

  validation {
    condition     = var.app_min_size >= 0
    error_message = "app_min_size must be zero or greater."
  }
}

variable "app_max_size" {
  type        = number
  default     = 10
  description = "Maximum number of ASG instances"

  validation {
    condition     = var.app_max_size >= 0
    error_message = "app_max_size must be zero or greater."
  }
}
