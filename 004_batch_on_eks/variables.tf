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
  default     = "batch-on-eks"
  description = "Resource name prefix"

  validation {
    condition     = length(var.prefix) > 0
    error_message = "prefix must not be empty."
  }
}

variable "amazon_linux2023_ami_id" {
  type        = string
  default     = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-x86_64"
  description = "Resolved by the aws_ssm_parameter data source"

  validation {
    condition     = can(regex("^/", var.amazon_linux2023_ami_id))
    error_message = "amazon_linux2023_ami_id must be an SSM parameter path starting with '/'."
  }
}

variable "kubernetes_version" {
  type        = string
  default     = "1.36"
  description = "EKS cluster Kubernetes version (1.XX)"

  validation {
    condition     = contains(["1.34", "1.35", "1.36"], var.kubernetes_version)
    error_message = "kubernetes_version must be one of: 1.34, 1.35, 1.36."
  }
}

variable "vscode_instance_type" {
  type        = string
  default     = "t3.medium"
  description = "EC2 instance type for the VS Code EC2 instance"
}
