variable "name" {
  type        = string
  default     = "vscode"
  description = "Name tag for the workbench instance, as the _monolithic template had it"

  validation {
    condition     = length(var.name) > 0
    error_message = "name must not be empty."
  }
}
variable "vpc_id" {
  type        = string
  description = "VPC ID where the instance's security group is created"

  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must be a valid VPC ID (e.g. vpc-0123456789abcdef0)."
  }
}
variable "subnet_id" {
  type        = string
  description = "Public subnet ID the instance is launched into. It has to be a public one: the bootstrap reaches github.com, the code-server release download and S3, and nothing puts a NAT gateway in front of this instance"

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
    condition     = var.key_name == null || (can(regex("^[ -~]+$", var.key_name)) && length(coalesce(var.key_name, "-")) <= 255)
    error_message = "key_name must be a string of printable ASCII characters (255 or fewer), or null."
  }
}
variable "instance_type" {
  type        = string
  default     = "t3.medium"
  description = "EC2 instance type, as the _monolithic template had it"

  validation {
    condition     = can(regex("^[a-z0-9-]+\\.[a-z0-9]+$", var.instance_type))
    error_message = "instance_type must be a valid EC2 instance type (e.g. t3.medium)."
  }
}
variable "ami_id" {
  type        = string
  description = "AMI ID for the instance. The root resolves the Amazon Linux parameter and passes the ID, so this module declares no data source (rules.md B-6/D-6)"

  validation {
    condition     = can(regex("^ami-[0-9a-f]+$", var.ami_id))
    error_message = "ami_id must be a valid AMI ID (e.g. ami-0123456789abcdef0)."
  }
}
variable "root_volume_size" {
  type        = number
  default     = null
  description = "Size in GiB of the root EBS volume. Null keeps the AMI's own size, which is what the _monolithic template got by not setting one; a fixed number smaller than a future AMI's snapshot would fail RunInstances"

  validation {
    condition     = var.root_volume_size == null || coalesce(var.root_volume_size, 8) >= 8
    error_message = "root_volume_size must be at least 8 GiB, or null to keep the AMI's size."
  }
}
variable "code_server_version" {
  type        = string
  default     = "4.102.3"
  description = "code-server release version to install, as the _monolithic template pinned it"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.code_server_version))
    error_message = "code_server_version must be a semantic version (e.g. 4.102.3)."
  }
}
variable "code_server_port" {
  type        = number
  default     = 8000
  description = "TCP port code-server binds to, and the port opened in the instance's security group"

  validation {
    condition     = var.code_server_port > 0 && var.code_server_port <= 65535
    error_message = "code_server_port must be a valid TCP port."
  }
}
variable "security_group_name" {
  type        = string
  default     = "vscode-sg"
  description = "Name of the security group created for the instance, as the _monolithic template named it"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]+$", var.security_group_name)) && length(var.security_group_name) <= 255 && !startswith(var.security_group_name, "sg-")
    error_message = "security_group_name must be 1-255 characters from the set AWS accepts for a security group name (a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*, no apostrophe) and must not start with \"sg-\", which EC2 reserves for security group IDs (rules.md F-1)."
  }
}
variable "security_group_description" {
  type        = string
  default     = "Security Group"
  description = "Description attached to the security group, as the _monolithic template had it. Changing it replaces the group (rules.md F-1)"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]+$", var.security_group_description)) && length(var.security_group_description) <= 255
    error_message = "security_group_description must be 1-255 characters from the set AWS accepts for a security group description: a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*. An apostrophe is NOT allowed - EC2 rejects CreateSecurityGroup with InvalidParameterValue at apply time (rules.md F-1)."
  }
}
variable "allow_inbound_from_anywhere" {
  type        = bool
  default     = true
  description = "Whether code_server_port accepts traffic from 0.0.0.0/0. True as the _monolithic template's InboundFromAnywhere defaulted. code-server runs with auth: none, so this is an unauthenticated editor on a public address whose instance role carries AdministratorAccess - set it false and use SSM Session Manager port forwarding for anything longer lived than a demo"
}
variable "iam_role_name_prefix" {
  type        = string
  description = "Prefix for the instance role and instance profile names. The provider appends a unique suffix"

  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_-]+$", var.iam_role_name_prefix)) && length(var.iam_role_name_prefix) <= 38
    error_message = "iam_role_name_prefix must be 1-38 characters from the set IAM accepts for a role name (name_prefix is capped at 38)."
  }
}
variable "iam_policy_arns" {
  type        = list(string)
  default     = ["arn:aws:iam::aws:policy/AdministratorAccess"]
  description = "IAM managed policy ARNs attached to the instance's role. AdministratorAccess as the _monolithic template attached it: this is a person's workbench, which rules.md A-5 exempts on purpose, and it also covers the SSM agent permissions every association in the root needs"

  validation {
    condition     = alltrue([for arn in var.iam_policy_arns : can(regex("^arn:aws[a-z-]*:iam::", arn))])
    error_message = "iam_policy_arns must contain valid IAM policy ARNs."
  }
}
variable "marker_file_path" {
  type        = string
  default     = null
  description = "Optional absolute directory in which to write the bootstrap completion marker (touch <path>/userdata) as the last line of the user data. When null, no marker is written and nothing downstream can wait on it (rules.md B-4/D-5)"

  validation {
    condition     = var.marker_file_path == null || startswith(coalesce(var.marker_file_path, "/"), "/")
    error_message = "marker_file_path must be an absolute path starting with '/', or null."
  }
}
variable "additional_user_data" {
  type        = string
  default     = ""
  description = "Shell script appended after code-server is started and before the completion marker is written. The root uses it to clone the game sample and upload the build artifacts"

  validation {
    condition     = length(var.additional_user_data) < 12000
    error_message = "additional_user_data must stay under 12000 characters, leaving room for the base bootstrap script inside EC2's 16 KB user data limit."
  }
}
