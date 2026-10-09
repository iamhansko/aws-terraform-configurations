variable "name" {
  type        = string
  default     = "governance-bastion"
  description = "Name tag for the instance. The caller's variable of the same name explains why this particular string matters to the Config rule"

  validation {
    condition     = length(var.name) > 0
    error_message = "name must not be empty."
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
  description = "Subnet the instance is launched into"

  validation {
    condition     = can(regex("^subnet-[0-9a-f]+$", var.subnet_id))
    error_message = "subnet_id must be a valid subnet ID (e.g. subnet-0123456789abcdef0)."
  }
}
variable "ami_id" {
  type        = string
  description = "AMI the instance is launched from. Taken as an id rather than looked up here, so this module does not need to know whether it came from an SSM public parameter or a literal (rules.md B-6) - and so the lookup is not inside a module that could later carry depends_on (rules.md D-6)"

  validation {
    condition     = can(regex("^ami-[0-9a-f]+$", var.ami_id))
    error_message = "ami_id must be a valid AMI ID (e.g. ami-0123456789abcdef0)."
  }
}
variable "instance_type" {
  type        = string
  default     = "t3.micro"
  description = "Instance type, as the _monolithic template had it"

  validation {
    condition     = can(regex("^[a-z0-9]+\\.[a-z0-9]+$", var.instance_type))
    error_message = "instance_type must be a valid EC2 instance type (e.g. t3.micro)."
  }
}
variable "key_name" {
  type        = string
  default     = null
  description = "EC2 key pair used to launch the instance. Null leaves the instance reachable only through SSM Session Manager, which is enough for everything this project does"

  validation {
    condition     = var.key_name == null || can(regex("^[ -~]{1,255}$", var.key_name))
    error_message = "key_name must be a string of printable ASCII characters (255 or fewer), or null."
  }
}
variable "security_group_name" {
  type        = string
  default     = "governance-bastion-sg"
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
variable "security_group_description" {
  type        = string
  default     = "Security Group"
  description = "Description attached to that group. Changing it replaces the group, because AWS has no API to modify a security group description (rules.md F-1)"

  validation {
    condition     = length(var.security_group_description) > 0
    error_message = "security_group_description must not be empty. EC2 rejects an empty description, and omitting the attribute entirely makes the provider write \"Managed by Terraform\"."
  }
  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.security_group_description))
    error_message = "security_group_description must be 1-255 characters from the set AWS accepts for a security group description: a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*. An apostrophe is NOT allowed - writing \"the instance's security group\" is the usual way this happens, and EC2 rejects CreateSecurityGroup with InvalidParameterValue partway through apply rather than at plan."
  }
}
variable "ingress_cidr_blocks" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = "Source ranges allowed to reach the SSH and code-server ports, as the _monolithic template had them. code-server runs with authentication disabled, so this list is the only thing standing in front of a browser shell on an instance whose role carries AdministratorAccess"

  validation {
    condition     = length(var.ingress_cidr_blocks) > 0 && alltrue([for cidr in var.ingress_cidr_blocks : can(cidrhost(cidr, 0))])
    error_message = "ingress_cidr_blocks must be a non-empty list of IPv4 CIDR blocks (e.g. 203.0.113.0/24)."
  }
}
variable "ssh_port" {
  type        = number
  default     = 22
  description = "SSH port opened on the instance, as the _monolithic template had it"

  validation {
    condition     = var.ssh_port > 0 && var.ssh_port <= 65535
    error_message = "ssh_port must be a valid TCP port."
  }
}
variable "code_server_port" {
  type        = number
  default     = 8000
  description = "Port code-server binds to and the port opened for it. One value feeding the config file it writes, the security group rule and the URL in the outputs (rules.md B-5)"

  validation {
    condition     = var.code_server_port > 0 && var.code_server_port <= 65535
    error_message = "code_server_port must be a valid TCP port."
  }
}
variable "code_server_version" {
  type        = string
  default     = "4.100.3"
  description = "code-server release to install, as the _monolithic template had it"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.code_server_version))
    error_message = "code_server_version must be a semantic version (e.g. 4.100.3)."
  }
}
variable "python_version" {
  type        = string
  default     = "3.12"
  description = "Python the bootstrap installs and links as /usr/bin/python, as the _monolithic template had it. Independent of the Lambda runtime - this one is for editing the handler on the instance, not for running it"

  validation {
    condition     = can(regex("^3\\.[0-9]+$", var.python_version))
    error_message = "python_version must be a 3.x version available in the Amazon Linux 2023 repositories (e.g. 3.12)."
  }
}
variable "associate_public_ip_address" {
  type        = bool
  default     = true
  description = "Whether the instance gets a public IP, as the _monolithic template had it"
}
variable "iam_policy_arns" {
  type = list(string)
  default = [
    "arn:aws:iam::aws:policy/AdministratorAccess",
    "arn:aws:iam::aws:policy/IAMFullAccess",
  ]
  description = "Managed policies attached to the instance's role. Deliberately broad: this is the human workbench rules.md H-1 is written around, and the demo run from it launches instances, reads Config evaluations and attaches and detaches role policies by hand. The caller's variable records that this breadth is kept rather than overlooked (rules.md A-5)"

  validation {
    condition     = alltrue([for arn in var.iam_policy_arns : can(regex("^arn:aws[a-z-]*:iam::", arn))])
    error_message = "iam_policy_arns must contain IAM policy ARNs."
  }
}
variable "role_name_prefix" {
  type        = string
  default     = "governance-bastion-"
  description = "Prefix for the generated names of the instance's role and instance profile. The _monolithic template left the role's name to the provider and called the profile BastionEc2InstanceProfile; a prefix gives both a readable name without a fixed one, which matters more than usual in a project whose subject is which instance profile holds which role"

  validation {
    condition     = can(regex("^[\\w+=,.@-]{1,32}$", var.role_name_prefix))
    error_message = "role_name_prefix must be 1-32 characters from the set IAM accepts for role and instance profile names (letters, digits and _+=,.@-), leaving room for the generated suffix inside the 64 character role name limit."
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
  description = "Optional absolute directory in which the bootstrap drops a completion marker (touch <path>/userdata) as its very last step, for SSM associations that must not start until it has finished. Null creates no marker, which is why this is a template directive rather than an unconditional line (rules.md B-4)"

  validation {
    condition     = var.marker_file_path == null || can(regex("^/", var.marker_file_path))
    error_message = "marker_file_path must be an absolute path starting with '/', or null."
  }
}
variable "additional_user_data" {
  type        = string
  default     = ""
  description = "Shell appended after code-server is running and before the marker is written. Everything in here therefore happens while an association waiting on the marker is still waiting, which is the point"

  validation {
    condition     = length(var.additional_user_data) < 12000
    error_message = "additional_user_data must stay under 12000 characters, leaving room for the base bootstrap inside EC2's 16 KB user data limit."
  }
}
