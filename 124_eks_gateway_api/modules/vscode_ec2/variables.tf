variable "name" {
  type        = string
  default     = "vscode"
  description = "Name tag for the VS Code EC2 instance, as the _monolithic template had it"

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
  default     = "t3.medium"
  description = "EC2 instance type for the VS Code EC2 instance, as the _monolithic template had it"

  validation {
    condition     = can(regex("^[a-z0-9]+\\.[a-z0-9]+$", var.instance_type))
    error_message = "instance_type must be a valid EC2 instance type (e.g. t3.medium)."
  }
}
variable "ami_ssm_parameter_name" {
  type        = string
  default     = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-x86_64"
  description = "SSM parameter path resolved to the AMI ID for the instance, as the _monolithic template's AmiId parameter defaulted to"

  validation {
    condition     = can(regex("^/", var.ami_ssm_parameter_name))
    error_message = "ami_ssm_parameter_name must be an absolute SSM parameter path starting with '/'."
  }
}
variable "root_volume_size" {
  type        = number
  default     = 30
  description = "Size in GiB of the instance's root EBS volume. The _monolithic template left this at the AMI default, which is too small once the toolchain and a few container images land on it"

  validation {
    condition     = var.root_volume_size >= 8
    error_message = "root_volume_size must be at least 8 GiB."
  }
}
variable "code_server_version" {
  type        = string
  default     = "4.140.0"
  description = "code-server release version to install. Pinned rather than resolved from the GitHub releases API at boot, as the _monolithic template did: that made the installed version depend on the day the stack was created, and failed closed when the unauthenticated API rate limit was hit - jq then parsed an error document and VSC_VERSION came out empty, so the download URL was malformed"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.code_server_version))
    error_message = "code_server_version must be a semantic version (e.g. 4.140.0)."
  }
}
variable "code_server_port" {
  type        = number
  default     = 8000
  description = "TCP port code-server binds to, and the port opened in the instance's security group, as the _monolithic template had it"

  validation {
    condition     = var.code_server_port > 0 && var.code_server_port <= 65535
    error_message = "code_server_port must be a valid TCP port."
  }
}
variable "security_group_name" {
  type        = string
  default     = "vscode-sg"
  description = "Name of the security group created for the instance, as the _monolithic template had it"

  validation {
    condition     = length(var.security_group_name) > 0
    error_message = "security_group_name must not be empty."
  }
  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.security_group_name)) && !startswith(var.security_group_name, "sg-")
    error_message = "security_group_name must be 1-255 characters from the set AWS accepts for a security group name (a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*, no apostrophe) and must not start with \"sg-\", which EC2 reserves for security group IDs."
  }
}
variable "security_group_description" {
  type        = string
  default     = "Security group for the VS Code EC2 instance"
  description = "Description attached to the instance's security group. Changing it replaces the group, because AWS has no API to edit a group description (rules.md F-1)"

  validation {
    condition     = length(var.security_group_description) > 0
    error_message = "security_group_description must not be empty. AWS rejects an empty description, and omitting it would make the provider write \"Managed by Terraform\" instead."
  }
  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.security_group_description))
    error_message = "security_group_description must be 1-255 characters from the set AWS accepts for a security group description: a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*. An apostrophe is NOT allowed - EC2 rejects the CreateSecurityGroup call with InvalidParameterValue, which otherwise only surfaces at apply time (rules.md F-1)."
  }
}
variable "allow_inbound_from_anywhere" {
  type        = bool
  default     = false
  description = "Whether to allow inbound access to code_server_port from 0.0.0.0/0. False, as the _monolithic template's InboundFromAnywhere parameter defaulted to - a bool here where that template used a string validated against [\"True\", \"False\"]. code-server runs with auth: none, so opening this exposes an unauthenticated IDE with an AdministratorAccess instance role to the internet; reach it through SSM Session Manager port forwarding instead"
}
variable "ingress_cidr_blocks" {
  type        = list(string)
  default     = []
  description = "CIDR blocks allowed inbound on code_server_port, applied in addition to allow_inbound_from_anywhere. The narrow alternative to opening the port to everyone"

  validation {
    condition     = alltrue([for cidr in var.ingress_cidr_blocks : can(cidrhost(cidr, 0))])
    error_message = "ingress_cidr_blocks must contain valid IPv4 CIDR blocks."
  }
}
variable "associate_public_ip_address" {
  type        = bool
  default     = true
  description = "Whether to associate a public IP address with the instance, as the _monolithic template's NetworkInterfaces entry had it"
}
variable "iam_policy_arns" {
  type        = list(string)
  default     = ["arn:aws:iam::aws:policy/AdministratorAccess"]
  description = "IAM managed policy ARNs attached to the VS Code EC2 instance's IAM role, as the _monolithic template had it. AdministratorAccess keeps the hands-on demo workflow (eksctl, helm, kubectl against any resource) unblocked; scope this down for anything longer lived. This is the human's workbench, so rules.md A-5 exempts it - a controller role would not be"

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
  description = "Optional absolute directory in which to create a userdata completion marker file (touch <path>/userdata), for SSM associations that must wait until the bootstrap finished. When null, no marker file is created (rules.md B-4)"

  validation {
    condition     = var.marker_file_path == null || can(regex("^/", var.marker_file_path))
    error_message = "marker_file_path must be an absolute path starting with '/', or null."
  }
}
variable "additional_user_data" {
  type        = string
  default     = ""
  description = "Additional shell script content appended after code-server is started (e.g. installing kubectl/helm/eksctl). Rendered before the completion marker, so a step waiting on that marker waits for all of it (rules.md B-4/H-2)"

  validation {
    condition     = length(var.additional_user_data) < 12000
    error_message = "additional_user_data must stay under 12000 characters, leaving room for the base bootstrap script inside EC2's 16 KB user data limit."
  }
}
