variable "instance_name" {
  type        = string
  description = "Name tag of the workbench instance and of its Elastic IP"

  validation {
    condition     = length(var.instance_name) > 0
    error_message = "instance_name must not be empty."
  }
}
variable "vpc_id" {
  type        = string
  description = "VPC the security group is created in. The hub VPC here: the workbench sits on the internet-facing side and reaches everything else across the peering connection"

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
  description = "AMI the instance launches from. An ami- ID rather than an SSM parameter path, so this module does not have to know where the ID came from (rules.md B-6) and so the lookup stays in the root, where it is read at plan time rather than deferred by this module's depends_on (rules.md D-6)"

  validation {
    condition     = can(regex("^ami-[0-9a-f]+$", var.ami_id))
    error_message = "ami_id must be a valid AMI ID (e.g. ami-0123456789abcdef0)."
  }
}
variable "instance_type" {
  type        = string
  description = "Instance type for the workbench"

  validation {
    condition     = can(regex("^[a-z0-9]+\\.[a-z0-9]+$", var.instance_type))
    error_message = "instance_type must be a valid EC2 instance type (e.g. t3.small)."
  }
}
variable "key_name" {
  type        = string
  default     = null
  description = "Optional EC2 key pair name. When null the instance is reachable only through SSM Session Manager"

  validation {
    condition     = var.key_name == null || can(regex("^[ -~]{1,255}$", var.key_name))
    error_message = "key_name must be a string of printable ASCII characters (255 or fewer), or null."
  }
}
variable "root_volume_size" {
  type        = number
  description = "Root volume size in GiB. This instance builds four container images, so the 8 GiB AL2023 default that the _monolithic template inherited is not enough - see main.tf"

  validation {
    condition     = var.root_volume_size >= 8
    error_message = "root_volume_size must be at least 8 GiB."
  }
}
variable "associate_public_ip_address" {
  type        = bool
  description = "Whether the instance gets a public IP at launch. An Elastic IP is associated separately, but the launch-time address is what lets the bootstrap reach the internet before that association completes"
}
variable "code_server_version" {
  type        = string
  description = "code-server release to install. The _monolithic template pinned 4.100.3"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.code_server_version))
    error_message = "code_server_version must be a semantic version (e.g. 4.100.3)."
  }
}
variable "code_server_port" {
  type        = number
  description = "Port code-server binds to, and the port opened in the security group"

  validation {
    condition     = var.code_server_port > 0 && var.code_server_port <= 65535
    error_message = "code_server_port must be a valid TCP port."
  }
}
variable "ssh_port" {
  type        = number
  description = "Port sshd is moved to. The _monolithic template used 10100 and opened only that, leaving 22 closed"

  validation {
    condition     = var.ssh_port > 0 && var.ssh_port <= 65535
    error_message = "ssh_port must be a valid TCP port."
  }
  validation {
    condition     = var.ssh_port != var.code_server_port
    error_message = "ssh_port must differ from code_server_port: sshd and code-server cannot both bind the same port, and the one that loses the race keeps restarting under its systemd Restart=always."
  }
}
variable "python_version" {
  type        = string
  description = "Python minor version installed and symlinked to /usr/bin/python. The _monolithic template installed 3.12 explicitly rather than taking the AL2023 default"

  validation {
    condition     = can(regex("^3\\.[0-9]+$", var.python_version))
    error_message = "python_version must be a 3.x minor version (e.g. 3.12)."
  }
}
variable "ingress_cidr_blocks" {
  type        = list(string)
  description = "Source ranges allowed inbound on code_server_port and ssh_port. The _monolithic template used 0.0.0.0/0 for both, and code-server here runs with auth: none - so the URL is the only credential"

  validation {
    condition     = alltrue([for cidr in var.ingress_cidr_blocks : can(cidrhost(cidr, 0))])
    error_message = "ingress_cidr_blocks must contain valid IPv4 CIDR blocks."
  }
}
variable "security_group_name" {
  type        = string
  description = "Name of the security group created for the instance"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.security_group_name)) && !startswith(var.security_group_name, "sg-")
    error_message = "security_group_name must be 1-255 characters from the set AWS accepts for a security group name (a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*, no apostrophe) and must not start with \"sg-\", which EC2 reserves for security group IDs."
  }
}
variable "security_group_description" {
  type        = string
  description = "Description of the instance security group"

  validation {
    condition     = length(var.security_group_description) > 0
    error_message = "security_group_description must not be empty."
  }
  validation {
    # rules.md F-1. The _monolithic template's description here was "Security Group for Bastion
    # EC2 SSH Connection" - no apostrophe, so it happened to pass. "the workbench's security
    # group" would not, and the rejection arrives from CreateSecurityGroup during apply, after
    # both VPCs and every subnet exist.
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.security_group_description))
    error_message = "security_group_description must be 1-255 characters from the set AWS accepts for a security group description: a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*. An apostrophe is NOT allowed - EC2 rejects the CreateSecurityGroup call with InvalidParameterValue, which otherwise only surfaces at apply time."
  }
}
variable "iam_role_name_prefix" {
  type        = string
  description = "Prefix for the generated role and instance profile names. A prefix rather than the template's fixed Ec2AdminRole-<uuid slice>: the uuid existed only to stand in for AWS::StackId, and name_prefix is the provider's own way of getting the same uniqueness"

  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_-]{1,38}$", var.iam_role_name_prefix))
    error_message = "iam_role_name_prefix must be 1-38 characters from the set IAM accepts in a role name, leaving room for the generated suffix inside the 64 character limit."
  }
}
variable "iam_policy_arns" {
  type        = list(string)
  description = "Managed policy ARNs attached to the instance role. Broad on purpose - rules.md A-5 narrows the automated roles and excludes the workbench, because a person drives this one by hand. See the attachment in main.tf for what that hand needs to do here"

  validation {
    condition     = length(var.iam_policy_arns) > 0
    error_message = "iam_policy_arns must contain at least one policy: without one the bootstrap's AWS calls and every association the root attaches fail with AccessDenied."
  }
  validation {
    condition     = alltrue([for arn in var.iam_policy_arns : can(regex("^arn:aws:iam::", arn))])
    error_message = "iam_policy_arns must contain valid IAM policy ARNs."
  }
}
variable "extra_security_group_ids" {
  type        = list(string)
  default     = []
  description = "Additional security group IDs attached to the instance. The module never looks these resources up itself (rules.md B-6)"

  validation {
    condition     = alltrue([for id in var.extra_security_group_ids : can(regex("^sg-[0-9a-f]+$", id))])
    error_message = "extra_security_group_ids must contain valid security group IDs (e.g. sg-0123456789abcdef0)."
  }
}
variable "marker_file_path" {
  type        = string
  default     = null
  description = "Optional absolute directory for the bootstrap completion marker (touch <path>/userdata), for SSM associations that must not start before the bootstrap finished. When null no marker is created (rules.md B-4). Re-exposed as an output so the root references one value rather than keeping its own copy (rules.md B-5)"

  validation {
    condition     = var.marker_file_path == null || can(regex("^/", var.marker_file_path))
    error_message = "marker_file_path must be an absolute path starting with '/', or null."
  }
}
variable "additional_user_data" {
  type        = string
  default     = ""
  description = "Shell script appended after code-server is started and before the marker is written. This is where the root installs the tools this demo needs and registers the hub load balancer's targets"

  validation {
    condition     = length(var.additional_user_data) < 10000
    error_message = "additional_user_data must stay under 10000 characters, leaving room for the base bootstrap inside EC2's 16 KB user data limit - EC2 rejects an oversized script with InvalidParameterValue at RunInstances."
  }
}
