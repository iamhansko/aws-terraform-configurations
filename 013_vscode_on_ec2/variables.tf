variable "aws_region" {
  type        = string
  default     = null
  description = "Target AWS region. When null, falls back to the provider default chain (AWS_REGION, profile, etc.)"
}
variable "prefix" {
  type        = string
  default     = "wsi"
  description = "Prefix for the network resources' Name tags (\"wsi\" produces wsi-vpc, wsi-igw, wsi-public-a, ...)"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*$", var.prefix))
    error_message = "prefix must be lowercase alphanumeric, optionally with hyphens."
  }
}
variable "vpc_cidr_block" {
  type        = string
  default     = "10.1.0.0/16"
  description = "CIDR block for the VPC"

  validation {
    condition     = can(cidrhost(var.vpc_cidr_block, 0))
    error_message = "vpc_cidr_block must be a valid IPv4 CIDR block (e.g. 10.1.0.0/16)."
  }
}
variable "key_name" {
  type        = string
  default     = "wsi-key"
  description = "Name of the EC2 key pair created for the VS Code instance"

  validation {
    condition     = can(regex("^[ -~]{1,255}$", var.key_name))
    error_message = "key_name must be a non-empty string of printable ASCII characters, 255 characters or fewer."
  }
}
variable "vscode_name" {
  type        = string
  default     = "wsi-bastion-ec2"
  description = "Name tag for the VS Code EC2 instance"

  validation {
    condition     = length(var.vscode_name) > 0
    error_message = "vscode_name must not be empty."
  }
}
variable "vscode_instance_type" {
  type        = string
  default     = "t3.small"
  description = "EC2 instance type for the VS Code EC2 instance"

  validation {
    condition     = can(regex("^[a-z0-9]+\\.[a-z0-9]+$", var.vscode_instance_type))
    error_message = "vscode_instance_type must be a valid EC2 instance type (e.g. t3.small)."
  }
}
variable "vscode_iam_policy_arns" {
  type = list(string)
  default = [
    "arn:aws:iam::aws:policy/PowerUserAccess",
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
  ]
  description = "IAM managed policy ARNs attached to the instance's role. PowerUserAccess keeps the hands-on workflow unblocked without granting IAM write access, and AmazonSSMManagedInstanceCore is listed explicitly because SSM is what writes the README onto the instance and what allows Session Manager access when the code-server port stays closed (rules.md H-2)"

  validation {
    condition     = alltrue([for arn in var.vscode_iam_policy_arns : can(regex("^arn:aws:iam::", arn))])
    error_message = "vscode_iam_policy_arns must contain valid IAM policy ARNs."
  }
}
variable "allow_inbound_from_anywhere" {
  type        = bool
  default     = true
  description = "Whether to allow inbound access to the code-server port (8000) from 0.0.0.0/0. code-server runs with auth disabled, so leaving this true publishes an unauthenticated IDE with shell access to the internet. Set false and reach it through SSM Session Manager port forwarding instead"
}
variable "install_docker" {
  type        = bool
  default     = true
  description = "Whether to install Docker on the instance. A real daemon on the host is the one thing that cannot be replaced by a Terraform provider, so it stays part of the bootstrap (rules.md E-1/H-1)"
}
variable "install_kubernetes_tools" {
  type        = bool
  default     = false
  description = "Whether to also install kubectl, eksctl and helm, which is what the _monolithic project's scripts/kubectl.sh variant did by hand-swapping the user data script. False by default because this root module has no EKS cluster: the five-tool workbench is required only when a cluster lives in the same root (rules.md H-1), and nothing here would configure a kubeconfig. Set true when pointing the instance at a cluster created elsewhere"
}
variable "kubectl_download_version" {
  type        = string
  default     = "1.33.3/2025-08-03"
  description = "Version and release-date path segment of the kubectl binary, from the amazon-eks S3 bucket layout (<version>/<date>). Only used when install_kubernetes_tools is true"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+/[0-9]{4}-[0-9]{2}-[0-9]{2}$", var.kubectl_download_version))
    error_message = "kubectl_download_version must look like 1.33.3/2025-08-03."
  }
}
variable "marker_file_path" {
  type        = string
  default     = "/run/terraform"
  description = "Directory holding the bootstrap marker files, shared between the vscode_ec2 module (which touches <path>/userdata as the last step of its user data) and the SSM association that polls for it before writing the README (rules.md D-5/H-2). Under /run so the markers vanish on reboot rather than making a stale file look like a completed bootstrap"

  validation {
    condition     = can(regex("^/", var.marker_file_path))
    error_message = "marker_file_path must be an absolute path starting with '/'."
  }
}
variable "readme_timeout_seconds" {
  type        = number
  default     = 900
  description = "How long the SSM association waits for the README command to report success. It has to cover the whole instance bootstrap, since the command's first act is to wait for the user data marker file"

  validation {
    condition     = var.readme_timeout_seconds > 0
    error_message = "readme_timeout_seconds must be greater than zero."
  }
}
