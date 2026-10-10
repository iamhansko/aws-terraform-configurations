variable "instance_name" {
  type        = string
  default     = "vscode"
  description = "Name tag for the instance"
  validation {
    condition     = length(var.instance_name) > 0
    error_message = "instance_name must not be empty."
  }
}
variable "vpc_id" {
  type        = string
  description = "VPC the instance's security group is created in"
  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must be a valid VPC ID (e.g. vpc-0123456789abcdef0)."
  }
}
variable "subnet_id" {
  type        = string
  description = "Public subnet the instance is launched into"
  validation {
    condition     = can(regex("^subnet-[0-9a-f]+$", var.subnet_id))
    error_message = "subnet_id must be a valid subnet ID (e.g. subnet-0123456789abcdef0)."
  }
}
variable "ami_id" {
  type        = string
  description = "AMI the instance boots. Resolved by the caller, so this module takes an ami- id and does not have to know where it came from (rules.md B-6)"
  validation {
    condition     = can(regex("^ami-[0-9a-f]+$", var.ami_id))
    error_message = "ami_id must be a valid AMI ID (e.g. ami-0123456789abcdef0)."
  }
}
variable "instance_type" {
  type        = string
  default     = "t3.medium"
  description = "EC2 instance type"
  validation {
    condition     = can(regex("^[a-z0-9]+\\.[a-z0-9]+$", var.instance_type))
    error_message = "instance_type must be a valid EC2 instance type (e.g. t3.medium)."
  }
}
variable "key_name" {
  type        = string
  default     = null
  description = "EC2 key pair used to launch the instance. When null the instance has no key and is reachable only through SSM Session Manager"
  validation {
    condition     = var.key_name == null || can(regex("^[ -~]{1,255}$", var.key_name))
    error_message = "key_name must be a string of printable ASCII characters (255 or fewer), or null."
  }
}
variable "root_volume_size" {
  type        = number
  default     = 30
  description = "Size in GiB of the root EBS volume"
  validation {
    condition     = var.root_volume_size >= 8
    error_message = "root_volume_size must be at least 8 GiB, the size of the AL2023 root snapshot."
  }
}
variable "associate_public_ip_address" {
  type        = bool
  default     = true
  description = "Whether the instance gets a public address. Required for code-server to be reachable and for the bootstrap to reach the internet, since this project has no NAT gateway"
}
variable "security_group_name" {
  type        = string
  default     = "vscode-sg"
  description = "Name of the instance's security group"
  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.security_group_name)) && !startswith(var.security_group_name, "sg-")
    error_message = "security_group_name must be 1-255 characters from the set AWS accepts for a security group name (a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*, no apostrophe) and must not start with \"sg-\", which EC2 reserves for security group IDs."
  }
}
variable "security_group_description" {
  type        = string
  default     = "Security Group"
  description = "Description attached to the instance's security group, as the _monolithic template worded it. Changing it replaces the group, because EC2 has no API for modifying a description (rules.md F-1)"
  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.security_group_description))
    error_message = "security_group_description must be 1-255 characters from the set AWS accepts for a security group description: a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*. An apostrophe is NOT allowed - EC2 rejects CreateSecurityGroup with InvalidParameterValue, which otherwise only surfaces partway through an apply (rules.md F-1)."
  }
}
variable "ingress_cidr_blocks" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = "Sources allowed to reach code_server_port. code-server runs with auth: none, so whatever can reach that port has a shell. Empty opens nothing, and the instance is then reachable only through Session Manager"
  validation {
    condition     = alltrue([for cidr in var.ingress_cidr_blocks : can(cidrhost(cidr, 0))])
    error_message = "ingress_cidr_blocks must contain valid IPv4 CIDR blocks (e.g. 203.0.113.0/24)."
  }
}
variable "ssh_ingress_cidr_blocks" {
  type        = list(string)
  default     = []
  description = "Sources allowed to reach ssh_port. Empty by default, which is what the _monolithic template had: it generated a key pair but opened no SSH port"
  validation {
    condition     = alltrue([for cidr in var.ssh_ingress_cidr_blocks : can(cidrhost(cidr, 0))])
    error_message = "ssh_ingress_cidr_blocks must contain valid IPv4 CIDR blocks (e.g. 203.0.113.0/24)."
  }
}
variable "code_server_port" {
  type        = number
  default     = 8000
  description = "Port code-server binds to and the security group opens"
  validation {
    condition     = var.code_server_port > 0 && var.code_server_port <= 65535
    error_message = "code_server_port must be a valid TCP port."
  }
}
variable "ssh_port" {
  type        = number
  default     = 22
  description = "Port the security group opens for SSH when ssh_ingress_cidr_blocks is not empty. The bootstrap does not move sshd"
  validation {
    condition     = var.ssh_port > 0 && var.ssh_port <= 65535
    error_message = "ssh_port must be a valid TCP port."
  }
}
variable "code_server_version" {
  type        = string
  default     = "4.104.2"
  description = "code-server release installed on the instance"
  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.code_server_version))
    error_message = "code_server_version must be a semantic version (e.g. 4.104.2)."
  }
}
variable "iam_name_prefix" {
  type        = string
  default     = "vscode-"
  description = "Prefix for the generated names of the instance role and instance profile"
  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_-]{1,38}$", var.iam_name_prefix))
    error_message = "iam_name_prefix must be 1-38 characters from the IAM name character set (letters, digits and +=,.@_-), leaving room for the suffix the provider appends within IAM's 64-character limit."
  }
}
variable "iam_policy_arns" {
  type        = list(string)
  default     = ["arn:aws:iam::aws:policy/AdministratorAccess"]
  description = "Managed policies attached to the instance role. rules.md A-5 narrows the automated roles and exempts the workbench: a person sits here and runs whatever the demo needs, and guessing that list in advance produces an AccessDenied halfway through"
  validation {
    condition     = alltrue([for arn in var.iam_policy_arns : can(regex("^arn:aws:iam::", arn))])
    error_message = "iam_policy_arns must contain valid IAM policy ARNs."
  }
}
variable "extra_security_group_ids" {
  type        = list(string)
  default     = []
  description = "Additional security groups attached to the instance. The module never looks these up itself (rules.md B-6)"
  validation {
    condition     = alltrue([for id in var.extra_security_group_ids : can(regex("^sg-[0-9a-f]+$", id))])
    error_message = "extra_security_group_ids must contain valid security group IDs (e.g. sg-0123456789abcdef0)."
  }
}
variable "marker_file_path" {
  type        = string
  default     = null
  description = "Optional absolute directory in which to create a bootstrap completion marker (touch <path>/userdata), for SSM associations that must wait until the bootstrap finished. When null, no marker is created"
  validation {
    condition     = var.marker_file_path == null || can(regex("^/", var.marker_file_path))
    error_message = "marker_file_path must be an absolute path starting with '/', or null."
  }
}
variable "additional_user_data" {
  type        = string
  default     = ""
  description = "Shell script appended after code-server is started and before the completion marker is written. Where the caller puts the tools and the work this particular project needs (rules.md B-4)"
  validation {
    condition     = length(var.additional_user_data) < 12000
    error_message = "additional_user_data must stay under 12000 characters, leaving room for the base bootstrap script inside EC2's 16 KB user data limit."
  }
}
