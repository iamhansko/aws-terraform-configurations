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
  default     = 80
  description = "Port the Apache web server listens on"

  validation {
    condition     = var.app_port > 0 && var.app_port <= 65535
    error_message = "app_port must be between 1 and 65535."
  }
}

variable "sample_app_zip_url" {
  type        = string
  default     = "https://static.us-east-1.prod.workshops.aws/public/93678d5d-ac27-459f-a7f2-088ae25e5522/assets/immersion-day-app-php7.zip"
  description = "URL of the sample PHP application archive extracted into /var/www/html"

  validation {
    condition     = can(regex("^https://", var.sample_app_zip_url))
    error_message = "sample_app_zip_url must be an HTTPS URL."
  }
}

variable "aws_sdk_php_zip_url" {
  type        = string
  default     = "https://docs.aws.amazon.com/aws-sdk-php/v3/download/aws.zip"
  description = "URL of the AWS SDK for PHP archive extracted into /var/www/html/vendor"

  validation {
    condition     = can(regex("^https://", var.aws_sdk_php_zip_url))
    error_message = "aws_sdk_php_zip_url must be an HTTPS URL."
  }
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
  default     = 4
  description = "Minimum number of instances in the ASG"

  validation {
    condition     = var.min_size >= 0
    error_message = "min_size must be zero or greater."
  }
}

variable "max_size" {
  type        = number
  default     = 10
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
