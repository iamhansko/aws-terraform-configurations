variable "vpc_id" {
  type        = string
  description = "VPC ID where the VS Code EC2 instance's security group is created"

  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must be a valid VPC ID (e.g. vpc-0123456789abcdef0)."
  }
}

variable "subnet_id" {
  type        = string
  description = "Public subnet ID the VS Code EC2 instance is launched into"

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
  default     = "t3.medium"
  description = "EC2 instance type for the VS Code EC2 instance"

  validation {
    condition     = can(regex("^[a-z0-9]+\\.[a-z0-9]+$", var.instance_type))
    error_message = "instance_type must be a valid EC2 instance type (e.g. t3.medium)."
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

variable "code_server_version" {
  type        = string
  default     = "4.102.3"
  description = "code-server release version to install"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.code_server_version))
    error_message = "code_server_version must be a semantic version (e.g. 4.102.3)."
  }
}

variable "allow_inbound_from_anywhere" {
  type        = bool
  default     = false
  description = "Whether the controlled inbound rules use 0.0.0.0/0. When false (the default), they use only my_ip_cidr"
}

variable "my_ip_cidr" {
  type        = string
  default     = null
  description = "Public IPv4 /32 supplied by the root and used as the controlled ingress source when allow_inbound_from_anywhere is false"

  validation {
    condition = (
      var.my_ip_cidr == null ||
      (can(regex("^[0-9]{1,3}(\\.[0-9]{1,3}){3}/32$", var.my_ip_cidr)) && can(cidrhost(var.my_ip_cidr, 0)))
    )
    error_message = "my_ip_cidr must be a valid IPv4 host CIDR such as 203.0.113.10/32, or null when allow_inbound_from_anywhere is true."
  }
  validation {
    condition     = var.allow_inbound_from_anywhere || var.my_ip_cidr != null
    error_message = "my_ip_cidr must be supplied when allow_inbound_from_anywhere is false. Pass the public IPv4 /32 detected by the root data.http.my_ip lookup."
  }
}

variable "iam_policy_arns" {
  type        = list(string)
  default     = ["arn:aws:iam::aws:policy/AdministratorAccess"]
  description = "IAM managed policy ARNs attached to the VS Code EC2 instance's IAM role"

  validation {
    condition     = alltrue([for arn in var.iam_policy_arns : can(regex("^arn:aws:iam::", arn))])
    error_message = "iam_policy_arns must contain valid IAM policy ARNs."
  }
}

variable "extra_security_group_ids" {
  type        = list(string)
  default     = []
  description = "Additional security group IDs attached to the instance (e.g. the EKS cluster security group, to allow API server access)"
}

variable "additional_user_data" {
  type        = string
  default     = ""
  description = "Additional shell script content merged in after code-server is started, appended to the base user_data script"
}
variable "marker_file_path" {
  type        = string
  default     = null
  description = "Optional absolute directory where user data drops its completion marker as its very last action. Null creates no marker, so a caller with no SSM Association to sequence does not have to know about it (rules.md B-4)"

  validation {
    condition     = var.marker_file_path == null || can(regex("^/", var.marker_file_path))
    error_message = "marker_file_path must be an absolute path starting with '/', or null."
  }
}
