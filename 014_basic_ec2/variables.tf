variable "aws_region" {
  type        = string
  default     = null
  description = "Target AWS region. When null, falls back to the provider default chain (AWS_REGION, profile, etc.)"
}
variable "prefix" {
  type        = string
  default     = "stem"
  description = "Prefix for the resources' Name tags (\"stem\" produces stem-vpc, stem-igw, stem-public-a, stem-public-ec2, ...)"

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
  default     = "stem-key"
  description = "Name of the EC2 key pair created for both instances"

  validation {
    condition     = can(regex("^[ -~]{1,255}$", var.key_name))
    error_message = "key_name must be a non-empty string of printable ASCII characters, 255 characters or fewer."
  }
}
variable "instance_type" {
  type        = string
  default     = "t3.small"
  description = "EC2 instance type for both instances"

  validation {
    condition     = can(regex("^[a-z0-9]+\\.[a-z0-9]+$", var.instance_type))
    error_message = "instance_type must be a valid EC2 instance type (e.g. t3.small)."
  }
}
variable "app_port" {
  type        = number
  default     = 3000
  description = "TCP port the demo app listens on. Opened on the public instance from the internet, and on the private instance only from the public instance's security group - which is what makes the two-tier reachability difference visible"

  validation {
    condition     = var.app_port > 0 && var.app_port <= 65535
    error_message = "app_port must be a valid TCP port."
  }
}
variable "app_repository_url" {
  type        = string
  default     = "https://github.com/iamhansko/find-different-color.git"
  description = "Git repository cloned onto the public instance and started as the demo app"

  validation {
    condition     = can(regex("^https://", var.app_repository_url))
    error_message = "app_repository_url must be an https:// Git URL."
  }
}
variable "app_node_major_version" {
  type        = number
  default     = 20
  description = "Node.js major version installed through nvm to run the demo app"

  validation {
    condition     = var.app_node_major_version > 0
    error_message = "app_node_major_version must be greater than zero."
  }
}
variable "nvm_version" {
  type        = string
  default     = "v0.40.3"
  description = "nvm release tag whose install script is fetched. Pinned rather than tracking master, so a change in the installer cannot silently alter how the app is bootstrapped"

  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+$", var.nvm_version))
    error_message = "nvm_version must be a release tag like v0.40.3."
  }
}
variable "allow_ssh_from_anywhere" {
  type        = bool
  default     = false
  description = "Whether to open port 22 on the public instance to 0.0.0.0/0, as the _monolithic template did. False by default: both instances carry AmazonSSMManagedInstanceCore, so Session Manager gives a shell on either of them without an inbound SSH rule"
}
variable "allow_app_from_anywhere" {
  type        = bool
  default     = true
  description = "Whether to open app_port on the public instance to 0.0.0.0/0, which is what makes the demo app reachable in a browser. Set false and reach it through SSM port forwarding instead"
}
