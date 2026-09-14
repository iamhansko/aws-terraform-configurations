variable "name" {
  type        = string
  default     = "vscode"
  description = "Name tag for the VS Code EC2 instance"

  validation {
    condition     = length(var.name) > 0
    error_message = "name must not be empty."
  }
}

variable "instance_type" {
  type        = string
  default     = "t3.medium"
  description = "EC2 instance type"

  validation {
    condition     = can(regex("^[a-z0-9]+\\.[a-z0-9]+$", var.instance_type))
    error_message = "instance_type must look like a valid EC2 instance type (e.g. t3.medium)."
  }
}

variable "ami_id" {
  type        = string
  description = "AMI ID to launch the instance from"

  validation {
    condition     = can(regex("^ami-[0-9a-f]+$", var.ami_id))
    error_message = "ami_id must be a valid AMI ID (e.g. ami-0123456789abcdef0)."
  }
}

variable "key_name" {
  type        = string
  description = "EC2 key pair name to attach to the instance"

  validation {
    condition     = length(var.key_name) > 0
    error_message = "key_name must not be empty."
  }
}

variable "vpc_id" {
  type        = string
  description = "VPC ID where the security group is created"

  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must be a valid VPC ID (e.g. vpc-0123456789abcdef0)."
  }
}

variable "subnet_id" {
  type        = string
  description = "Subnet ID where the instance is launched"

  validation {
    condition     = can(regex("^subnet-[0-9a-f]+$", var.subnet_id))
    error_message = "subnet_id must be a valid subnet ID (e.g. subnet-0123456789abcdef0)."
  }
}

variable "associate_public_ip_address" {
  type        = bool
  default     = true
  description = "Whether to associate a public IP address with the instance"
}

variable "iam_policy_arns" {
  type        = list(string)
  default     = ["arn:aws:iam::aws:policy/AdministratorAccess"]
  description = "IAM managed policy ARNs attached to the instance's IAM role"

  validation {
    condition     = alltrue([for arn in var.iam_policy_arns : can(regex("^arn:aws:iam::", arn))])
    error_message = "iam_policy_arns must contain valid IAM policy ARNs."
  }
}

variable "marker_file_path" {
  type        = string
  default     = null
  description = "Optional absolute directory in which to create a userdata completion marker file (touch <path>/userdata). When null, no marker file is created."

  validation {
    condition     = var.marker_file_path == null || can(regex("^/", var.marker_file_path))
    error_message = "marker_file_path must be an absolute path starting with '/', or null."
  }
}

variable "additional_user_data" {
  type        = string
  default     = ""
  description = "Additional shell script content merged in after code-server is started, appended to the base user_data script"
}
