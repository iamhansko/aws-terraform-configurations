variable "name" {
  type        = string
  default     = "app-bastion"
  description = "Name tag for the instance, as the _monolithic template had it (app-bastion)"

  validation {
    condition     = length(var.name) > 0
    error_message = "name must not be empty."
  }
}
variable "vpc_id" {
  type        = string
  description = "VPC the instance's security group is created in. Injected rather than looked up (rules.md B-6)"

  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must be a valid VPC ID (e.g. vpc-0123456789abcdef0)."
  }
}
variable "subnet_id" {
  type        = string
  description = "Subnet the instance is launched into. A private subnet of the app VPC, as the _monolithic template had it (app-private-sn-a) - which is the point: this host has no way out except the transit gateway"

  validation {
    condition     = can(regex("^subnet-[0-9a-f]+$", var.subnet_id))
    error_message = "subnet_id must be a valid subnet ID (e.g. subnet-0123456789abcdef0)."
  }
}
variable "key_name" {
  type        = string
  default     = null
  description = "Optional EC2 key pair name. Nothing can use it here - there is no inbound rule and no route from outside the VPC - so it is attached for parity with the _monolithic template; SSM Session Manager is the way in"

  validation {
    condition     = var.key_name == null || can(regex("^[ -~]{1,255}$", var.key_name))
    error_message = "key_name must be a string of printable ASCII characters (255 or fewer), or null."
  }
}
variable "instance_type" {
  type        = string
  default     = "t3.medium"
  description = "EC2 instance type, as the _monolithic template had it"

  validation {
    condition     = can(regex("^[a-z0-9]+\\.[a-z0-9]+$", var.instance_type))
    error_message = "instance_type must be a valid EC2 instance type (e.g. t3.medium)."
  }
}
variable "ami_ssm_parameter_name" {
  type        = string
  default     = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-x86_64"
  description = "SSM parameter path resolved to the AMI ID, as the _monolithic template's amazon_linux2023_ami_id parameter defaulted to"

  validation {
    condition     = can(regex("^/", var.ami_ssm_parameter_name))
    error_message = "ami_ssm_parameter_name must be an absolute SSM parameter path starting with '/'."
  }
}
variable "root_volume_size" {
  type        = number
  default     = 30
  description = "Size in GiB of the root volume. The _monolithic template left this at the AMI default, which is tight once code-server is installed"

  validation {
    condition     = var.root_volume_size >= 8
    error_message = "root_volume_size must be at least 8 GiB."
  }
}
variable "code_server_version" {
  type        = string
  default     = "4.140.0"
  description = "code-server release to install. Pinned rather than looked up from the GitHub releases API at boot, which makes the version depend on the day of the apply and fails closed on the unauthenticated rate limit"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.code_server_version))
    error_message = "code_server_version must be a semantic version (e.g. 4.140.0)."
  }
}
variable "code_server_port" {
  type        = number
  default     = 8000
  description = "TCP port code-server binds to. It is reached by SSM port forwarding rather than through a security group rule, so this port is opened to nothing by default"

  validation {
    condition     = var.code_server_port > 0 && var.code_server_port <= 65535
    error_message = "code_server_port must be a valid TCP port."
  }
}
variable "dnf_packages" {
  type        = list(string)
  default     = ["git", "bind-utils"]
  description = "Packages installed before code-server. bind-utils is load-bearing rather than convenience: it provides dig, and the _monolithic template installed it for exactly that reason - querying an external resolver is the probe for the firewall's stateful DNS rule"

  validation {
    condition     = length(var.dnf_packages) > 0
    error_message = "dnf_packages must name at least one package; the demo's DNS probe needs dig from bind-utils."
  }
  validation {
    condition     = alltrue([for package in var.dnf_packages : can(regex("^[a-zA-Z0-9._+-]+$", package))])
    error_message = "dnf_packages entries are interpolated into a shell command, so each must be a plain package name - letters, digits, dots, underscores, plus signs or hyphens."
  }
}
variable "security_group_name" {
  type        = string
  default     = "vscode-sg"
  description = "Name of the security group created for the instance. The _monolithic template created none and attached the app VPC's default group instead (rules.md F-2)"

  validation {
    condition     = length(var.security_group_name) > 0
    error_message = "security_group_name must not be empty."
  }
  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.security_group_name)) && !startswith(var.security_group_name, "sg-")
    error_message = "security_group_name must be 1-255 characters from the set AWS accepts for a security group name (a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*, no apostrophe) and must not start with \"sg-\", which EC2 reserves for security group IDs (rules.md F-1)."
  }
}
variable "security_group_description" {
  type        = string
  default     = "Workbench in the app VPC, whose only route off the VPC is the transit gateway"
  description = "Description on the instance's security group. Changing it replaces the group, because AWS has no API to edit a group description (rules.md F-1)"

  validation {
    condition     = length(var.security_group_description) > 0
    error_message = "security_group_description must not be empty. AWS rejects an empty description, and omitting the argument would make the provider write \"Managed by Terraform\" instead."
  }
  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.security_group_description))
    error_message = "security_group_description must be 1-255 characters from the set AWS accepts for a security group description: a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*. An apostrophe is NOT allowed - EC2 rejects the CreateSecurityGroup call with InvalidParameterValue, and that failure surfaces only at apply time, after the VPCs, the transit gateway and the firewall have already been created (rules.md F-1)."
  }
}
variable "ingress_cidr_blocks" {
  type        = list(string)
  default     = []
  description = "CIDR blocks allowed inbound to code_server_port. Empty by default, and only an address inside these VPCs could ever work - the app VPC has no internet gateway (rules.md B-4)"

  validation {
    condition     = alltrue([for cidr in var.ingress_cidr_blocks : can(cidrhost(cidr, 0))])
    error_message = "ingress_cidr_blocks must contain valid IPv4 CIDR blocks."
  }
}
variable "egress_cidr_ipv4" {
  type        = string
  default     = "0.0.0.0/0"
  description = "Destination of the instance's egress rule. This is the rule that makes the whole project work - see the note above aws_vpc_security_group_egress_rule in main.tf for what its absence looks like"

  validation {
    condition     = can(cidrhost(var.egress_cidr_ipv4, 0))
    error_message = "egress_cidr_ipv4 must be a valid IPv4 CIDR block."
  }
}
variable "extra_security_group_ids" {
  type        = list(string)
  default     = []
  description = "Additional security group IDs attached to the instance. The module never looks these up itself (rules.md B-6)"

  validation {
    condition     = alltrue([for id in var.extra_security_group_ids : can(regex("^sg-[0-9a-f]+$", id))])
    error_message = "extra_security_group_ids must contain valid security group IDs (e.g. sg-0123456789abcdef0)."
  }
}
variable "associate_public_ip_address" {
  type        = bool
  default     = false
  description = "Whether to associate a public IP with the instance. False, as the _monolithic template had it, and it cannot usefully be true: the app VPC has no internet gateway, so a public address here is allocated, billed and unroutable in both directions"
}
variable "iam_policy_arns" {
  type = list(string)
  default = [
    "arn:aws:iam::aws:policy/AdministratorAccess",
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
  ]
  description = "Managed policies attached to the instance role, the same two the _monolithic template attached. See the root variable of the same name for why AdministratorAccess is kept (rules.md A-5) and why AmazonSSMManagedInstanceCore is required rather than convenient"

  validation {
    condition     = alltrue([for arn in var.iam_policy_arns : can(regex("^arn:aws:iam::", arn))])
    error_message = "iam_policy_arns must contain valid IAM policy ARNs."
  }
}
variable "metadata_http_tokens" {
  type        = string
  default     = "required"
  description = "Whether IMDSv2 is mandatory. Required, where the _monolithic template left EC2's default of optional - the role on this instance is AdministratorAccess"

  validation {
    condition     = contains(["required", "optional"], var.metadata_http_tokens)
    error_message = "metadata_http_tokens must be either required or optional."
  }
}
variable "metadata_hop_limit" {
  type        = number
  default     = 1
  description = "PUT response hop limit for the instance metadata service. One, so a credential fetch cannot be relayed out of a container on this host"

  validation {
    condition     = var.metadata_hop_limit >= 1 && var.metadata_hop_limit <= 64
    error_message = "metadata_hop_limit must be between 1 and 64."
  }
}
variable "marker_file_path" {
  type        = string
  default     = null
  description = "Optional absolute directory in which to touch a userdata completion marker, for SSM associations that must wait for the bootstrap. When null no marker is created (rules.md B-4)"

  validation {
    condition     = var.marker_file_path == null || can(regex("^/", var.marker_file_path))
    error_message = "marker_file_path must be an absolute path starting with '/', or null."
  }
}
variable "additional_user_data" {
  type        = string
  default     = ""
  description = "Shell script appended after code-server has been started and before the completion marker is touched, so anything waiting on that marker waits for all of it too (rules.md B-4/H-2)"

  validation {
    condition     = length(var.additional_user_data) < 12000
    error_message = "additional_user_data must stay under 12000 characters, leaving room for the base bootstrap inside EC2's 16 KB user data limit."
  }
}
