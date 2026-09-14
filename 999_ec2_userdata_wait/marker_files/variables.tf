variable "aws_region" {
  type        = string
  default     = null
  description = "Target AWS region. Defaults to the provider chain (AWS_REGION)."

  validation {
    condition     = var.aws_region == null || can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "aws_region must be a valid AWS region identifier (e.g. us-east-1) or null."
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

variable "vscode_instance_name" {
  type        = string
  default     = "vscode"
  description = "Name tag applied to the VS Code EC2 instance"
}

variable "vscode_instance_type" {
  type        = string
  default     = "t3.small"
  description = "EC2 instance type for the VS Code EC2 instance"
}

variable "key_pair_name" {
  type        = string
  default     = "ec2-keypair"
  description = "Name of the EC2 key pair created for the VS Code EC2 instance"
}

variable "marker_file_path" {
  type        = string
  default     = "/run/terraform"
  description = "Directory used to store the userdata completion marker file, shared between the vscode_ec2 module and the SSM associations that poll it"

  validation {
    condition     = can(regex("^/", var.marker_file_path))
    error_message = "marker_file_path must be an absolute path starting with '/'."
  }
}
