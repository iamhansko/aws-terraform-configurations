variable "vpc_id" {
  type        = string
  description = "VPC ID where the ASG instances' security group is created"

  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must be a valid VPC ID (e.g. vpc-0123456789abcdef0)."
  }
}

variable "subnet_ids" {
  type        = list(string)
  description = "Private subnet IDs the ASG instances are launched into"

  validation {
    condition     = length(var.subnet_ids) > 0
    error_message = "subnet_ids must contain at least one subnet ID."
  }
}

variable "key_name" {
  type        = string
  description = "EC2 key pair name used to launch instances"

  validation {
    condition     = length(var.key_name) > 0
    error_message = "key_name must not be empty."
  }
}

variable "instance_type" {
  type        = string
  default     = "t3.small"
  description = "EC2 instance type for the ASG instances"

  validation {
    condition     = can(regex("^[a-z0-9]+\\.[a-z0-9]+$", var.instance_type))
    error_message = "instance_type must be a valid EC2 instance type (e.g. t3.small)."
  }
}

variable "ami_ssm_parameter_name" {
  type        = string
  default     = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-x86_64"
  description = "SSM parameter path resolved to the AMI ID for the instances"

  validation {
    condition     = can(regex("^/", var.ami_ssm_parameter_name))
    error_message = "ami_ssm_parameter_name must be an absolute SSM parameter path starting with '/'."
  }
}

variable "app_port" {
  type        = number
  default     = 3000
  description = "Port the Node.js app listens on"

  validation {
    condition     = var.app_port > 0 && var.app_port <= 65535
    error_message = "app_port must be between 1 and 65535."
  }
}

variable "nodejs_version" {
  type        = string
  default     = "18"
  description = "Node.js major version installed via nvm"

  validation {
    condition     = can(regex("^[0-9]+$", var.nodejs_version))
    error_message = "nodejs_version must be a Node.js major version number (e.g. 18)."
  }
}

variable "app_repository_url" {
  type        = string
  default     = "https://github.com/jeanrauwers/node-multiplayer.git"
  description = "Git repository URL cloned onto each instance to run the Socket.IO game server"

  validation {
    condition     = can(regex("^https://", var.app_repository_url))
    error_message = "app_repository_url must be an HTTPS URL."
  }
}

variable "additional_user_data" {
  type        = string
  default     = ""
  description = "Additional shell script content appended after the base user_data script (e.g. writing ELB_DNS_NAME to .env before npm run start:game)"
}

variable "load_balancer_security_group_id" {
  type        = string
  description = "Security group ID of the load balancer, allowed to reach app_port on the ASG instances"

  validation {
    condition     = can(regex("^sg-[0-9a-f]+$", var.load_balancer_security_group_id))
    error_message = "load_balancer_security_group_id must be a valid security group ID (e.g. sg-0123456789abcdef0)."
  }
}

variable "bastion_security_group_id" {
  type        = string
  description = "Security group ID of the bastion EC2 instance, allowed SSH and app_port access to the ASG instances for troubleshooting"

  validation {
    condition     = can(regex("^sg-[0-9a-f]+$", var.bastion_security_group_id))
    error_message = "bastion_security_group_id must be a valid security group ID (e.g. sg-0123456789abcdef0)."
  }
}

variable "target_group_arns" {
  type        = list(string)
  description = "Target group ARNs the ASG registers its instances with"

  validation {
    condition     = length(var.target_group_arns) > 0
    error_message = "target_group_arns must contain at least one target group ARN."
  }
}

variable "min_size" {
  type        = number
  default     = 2
  description = "Minimum number of instances in the ASG"

  validation {
    condition     = var.min_size >= 0
    error_message = "min_size must be zero or greater."
  }
}

variable "max_size" {
  type        = number
  default     = 4
  description = "Maximum number of instances in the ASG"

  validation {
    condition     = var.max_size >= 0
    error_message = "max_size must be zero or greater."
  }
}

variable "target_cpu_utilization" {
  type        = number
  default     = 30
  description = "Target average CPU utilization (%) the ASG's TargetTrackingScaling policy scales towards"

  validation {
    condition     = var.target_cpu_utilization > 0 && var.target_cpu_utilization <= 100
    error_message = "target_cpu_utilization must be between 1 and 100."
  }
}

variable "prefix" {
  type        = string
  default     = "stem"
  description = "Resource name prefix, used to name the auto scaling policy"

  validation {
    condition     = length(var.prefix) > 0
    error_message = "prefix must not be empty."
  }
}
