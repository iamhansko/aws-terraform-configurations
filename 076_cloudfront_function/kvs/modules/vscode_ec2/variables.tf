variable "name" {
  type        = string
  default     = "vscode"
  description = "Name tag for the VS Code EC2 instance"

  validation {
    condition     = length(var.name) > 0
    error_message = "name must not be empty."
  }
}
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
  default     = null
  description = "Optional EC2 key pair name used to launch the instance. When null, the instance is reachable only through SSM Session Manager"

  validation {
    condition     = var.key_name == null || can(regex("^[ -~]{1,255}$", var.key_name))
    error_message = "key_name must be a string of printable ASCII characters (255 or fewer), or null."
  }
}
variable "instance_type" {
  type        = string
  default     = "t3.small"
  description = "EC2 instance type for the VS Code EC2 instance"

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
variable "root_volume_size" {
  type        = number
  default     = 30
  description = "Size in GiB of the instance's root EBS volume. The default AL2023 root volume is too small once container images and toolchains are pulled onto the instance"

  validation {
    condition     = var.root_volume_size >= 8
    error_message = "root_volume_size must be at least 8 GiB."
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
variable "code_server_port" {
  type        = number
  default     = 8000
  description = "TCP port code-server binds to. Opened to ingress_prefix_list_ids only when path_prefix is null; behind nginx, code-server binds to loopback and port 80 is opened to them instead"

  validation {
    condition     = var.code_server_port > 0 && var.code_server_port <= 65535
    error_message = "code_server_port must be a valid TCP port."
  }
  validation {
    # nginx takes 80 when path_prefix is set, and two listeners on one port leave code-server failing to bind
    # with nothing in Terraform to say so (rules.md B-1).
    condition     = var.path_prefix == null || var.code_server_port != 80
    error_message = "code_server_port must not be 80 when path_prefix is set, because nginx listens on 80 in front of it."
  }
}
variable "path_prefix" {
  type        = string
  default     = null
  description = "URL path code-server is served under through an nginx reverse proxy on port 80 (e.g. /code), which is how a CloudFront distribution reaches it here. Null serves code-server directly on code_server_port"

  validation {
    condition     = var.path_prefix == null || can(regex("^/[a-z0-9-]+$", coalesce(var.path_prefix, "/x")))
    error_message = "path_prefix must be a single path segment such as /code (lowercase letters, digits and hyphens), or null."
  }
}
variable "security_group_name" {
  type        = string
  default     = "vscode-ec2-sg"
  description = "Name of the security group created for the instance"

  validation {
    condition     = length(var.security_group_name) > 0
    error_message = "security_group_name must not be empty."
  }
  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.security_group_name)) && !startswith(var.security_group_name, "sg-")
    error_message = "security_group_name must be 1-255 characters from the set AWS accepts for a security group name (a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*, no apostrophe) and must not start with \"sg-\", which EC2 reserves for security group IDs."
  }
}
variable "ingress_prefix_list_ids" {
  type        = list(string)
  description = "Managed prefix list IDs allowed inbound on the listening port - 80 behind nginx, code_server_port otherwise. They are its only inbound sources: code-server has no authentication in front of it, so nothing else is admitted. For a CloudFront origin, pass the ID of com.amazonaws.global.cloudfront.origin-facing in the instance's region, which makes the distribution the way in"

  validation {
    # An empty list plans and applies cleanly and leaves the port with no inbound rule at all, so every
    # request to it - CloudFront's included - times out with nothing in Terraform to say why (rules.md B-1).
    condition     = length(var.ingress_prefix_list_ids) >= 1
    error_message = "ingress_prefix_list_ids must contain at least one managed prefix list ID, because it is the only inbound source of the listening port and an empty list leaves the instance unreachable. For a CloudFront origin, pass the ID of the com.amazonaws.global.cloudfront.origin-facing prefix list, for example from data.aws_ec2_managed_prefix_list."
  }
  validation {
    condition     = alltrue([for id in var.ingress_prefix_list_ids : can(regex("^pl-[0-9a-f]+$", id))])
    error_message = "ingress_prefix_list_ids must contain valid managed prefix list IDs (e.g. pl-3b927c52)."
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
  description = "IAM managed policy ARNs attached to the VS Code EC2 instance's IAM role. AdministratorAccess keeps the hands-on demo workflow unblocked - this is a person's workbench, not a controller (rules.md A-5) - and it covers AmazonSSMManagedInstanceCore, which the README association needs. Scope this down for anything longer lived"

  validation {
    condition     = alltrue([for arn in var.iam_policy_arns : can(regex("^arn:aws:iam::", arn))])
    error_message = "iam_policy_arns must contain valid IAM policy ARNs."
  }
}
variable "extra_security_group_ids" {
  type        = list(string)
  default     = []
  description = "Additional security group IDs attached to the instance (e.g. an EKS cluster security group, to allow API server access). The module never looks these resources up itself (rules.md B-6)"

  validation {
    condition     = alltrue([for id in var.extra_security_group_ids : can(regex("^sg-[0-9a-f]+$", id))])
    error_message = "extra_security_group_ids must contain valid security group IDs (e.g. sg-0123456789abcdef0)."
  }
}
variable "marker_file_path" {
  type        = string
  default     = null
  description = "Optional absolute directory in which to create a userdata completion marker file (touch <path>/userdata), for SSM associations that must wait until the bootstrap finished. When null, no marker file is created"

  validation {
    condition     = var.marker_file_path == null || can(regex("^/", var.marker_file_path))
    error_message = "marker_file_path must be an absolute path starting with '/', or null."
  }
}
variable "additional_user_data" {
  type        = string
  default     = ""
  description = "Additional shell script content appended after code-server is started, and before the completion marker is written (e.g. installing a CLI the README's commands need)"

  validation {
    condition     = length(var.additional_user_data) < 12000
    error_message = "additional_user_data must stay under 12000 characters, leaving room for the base bootstrap script inside EC2's 16 KB user data limit."
  }
}
