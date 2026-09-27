variable "vpc_id" {
  type        = string
  description = "VPC ID where the web EC2 instance's security group is created"

  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must be a valid VPC ID (e.g. vpc-0123456789abcdef0)."
  }
}

variable "subnet_id" {
  type        = string
  description = "Private subnet ID the web EC2 instance is launched into"

  validation {
    condition     = can(regex("^subnet-[0-9a-f]+$", var.subnet_id))
    error_message = "subnet_id must be a valid subnet ID (e.g. subnet-0123456789abcdef0)."
  }
}

variable "key_name" {
  type        = string
  description = "EC2 key pair name used to launch the instance"

  validation {
    condition     = length(var.key_name) > 0
    error_message = "key_name must not be empty."
  }
}

variable "instance_type" {
  type        = string
  default     = "t3.small"
  description = "EC2 instance type for the web EC2 instance"

  validation {
    condition     = can(regex("^[a-z0-9]+\\.[a-z0-9]+$", var.instance_type))
    error_message = "instance_type must be a valid EC2 instance type (e.g. t3.small)."
  }
}

variable "ami_ssm_parameter_name" {
  type        = string
  default     = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-x86_64"
  description = "SSM parameter path resolved to the AMI ID for the instance"

  validation {
    condition     = can(regex("^/", var.ami_ssm_parameter_name))
    error_message = "ami_ssm_parameter_name must be an absolute SSM parameter path starting with '/'."
  }
}

variable "ingress_source_security_groups" {
  type        = map(string)
  description = "Security group IDs allowed to reach the web server on port 80, keyed by a caller-chosen label, e.g. { pod = module.pod_security_group_policy.pod_security_group_id } so demo pods can reach this instance directly through their branch ENI. A map rather than a list because these IDs are another module's output, unknown until apply, and for_each needs statically known keys (rules.md B-8)"

  validation {
    condition     = length(var.ingress_source_security_groups) > 0
    error_message = "ingress_source_security_groups must contain at least one security group ID."
  }

  validation {
    condition     = alltrue([for label in keys(var.ingress_source_security_groups) : can(regex("^[a-zA-Z0-9._-]+$", label))])
    error_message = "ingress_source_security_groups keys are labels used in the rule descriptions, so each must be a non-empty string of letters, digits, dots, underscores or hyphens."
  }

  validation {
    condition     = alltrue([for id in values(var.ingress_source_security_groups) : can(regex("^sg-[0-9a-f]+$", id))])
    error_message = "ingress_source_security_groups must contain valid security group IDs (e.g. sg-0123456789abcdef0)."
  }
}
