variable "name" {
  type        = string
  default     = "ecs-cicd-bastion"
  description = "Name tag for the workbench instance and its elastic IP"

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
  description = "Public subnet ID the instance is launched into. It has to be a public one: the bootstrap and the associations that follow it reach github.com, Docker Hub and ECR, and nothing in this project puts a NAT gateway in front of a workbench"

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
  description = "EC2 instance type, as the _monolithic template had it"

  validation {
    condition     = can(regex("^[a-z0-9]+\\.[a-z0-9]+$", var.instance_type))
    error_message = "instance_type must be a valid EC2 instance type (e.g. t3.small)."
  }
}
variable "ami_id" {
  type        = string
  description = "AMI ID for the instance. The caller resolves the Amazon Linux parameter and passes the ID, so this module does not have to know where it came from (rules.md B-6) and the read stays out of a module that carries depends_on (rules.md D-6)"

  validation {
    condition     = can(regex("^ami-[0-9a-f]+$", var.ami_id))
    error_message = "ami_id must be a valid AMI ID (e.g. ami-0123456789abcdef0)."
  }
}
variable "root_volume_size" {
  type        = number
  default     = 30
  description = "Size in GiB of the root EBS volume. The stock AL2023 root volume runs out once the Docker Hub base image, the built image and the toolchain are on the instance, and a build that fails on no space reports it as a docker error"

  validation {
    condition     = var.root_volume_size >= 8
    error_message = "root_volume_size must be at least 8 GiB."
  }
}
variable "code_server_version" {
  type        = string
  default     = "4.102.3"
  description = "code-server release version to install. 4.100.3 is what the _monolithic template pinned"

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
variable "ssh_port" {
  type        = number
  default     = 2222
  description = "Port sshd is moved to by a drop-in under /etc/ssh/sshd_config.d, as the _monolithic template moved it. Only reachable when allow_inbound_from_anywhere is true"

  validation {
    condition     = var.ssh_port > 0 && var.ssh_port <= 65535
    error_message = "ssh_port must be a valid TCP port."
  }

  validation {
    condition     = var.ssh_port != var.code_server_port
    error_message = "ssh_port must differ from code_server_port. Both are opened on the same security group and bound on the same host, so the second service to start fails with \"Address already in use\"."
  }
}
variable "security_group_name" {
  type        = string
  default     = "bastion-ec2-sg"
  description = "Name of the security group created for the instance, as the _monolithic template named it"

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
  default     = "Security group for the code-server workbench that seeds the repository and pushes the first image"
  description = "Description attached to the security group"

  validation {
    condition     = length(var.security_group_description) > 0
    error_message = "security_group_description must not be empty."
  }
  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.security_group_description))
    error_message = "security_group_description must be 1-255 characters from the set AWS accepts for a security group description: a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*. An apostrophe is NOT allowed - EC2 rejects CreateSecurityGroup with InvalidParameterValue, and changing this value replaces the group (rules.md F-1)."
  }
}
variable "allow_inbound_from_anywhere" {
  type        = bool
  default     = true
  description = "Whether code_server_port and ssh_port accept traffic from 0.0.0.0/0. True as the _monolithic template had it. code-server here runs with auth: none, so this is an unauthenticated editor on a public address - leave it false and reach it through SSM Session Manager port forwarding for anything longer lived than a demo"
}
variable "associate_public_ip_address" {
  type        = bool
  default     = true
  description = "Whether to associate an auto-assigned public IP with the instance, in addition to the elastic IP"
}
variable "create_elastic_ip" {
  type        = bool
  default     = true
  description = "Whether to allocate an elastic IP and associate it with the instance, as the _monolithic template did. The address in the README and the outputs then survives a stop and start"
}
variable "iam_role_name" {
  type        = string
  default     = null
  description = "Explicit name for the instance's IAM role. Null lets the provider generate one, which is what keeps two copies of this project in one account from colliding - the _monolithic template hard-coded bastion-ec2-role and would have failed the second time with EntityAlreadyExists"

  validation {
    condition     = var.iam_role_name == null || can(regex("^[a-zA-Z0-9+=,.@_-]{1,64}$", var.iam_role_name))
    error_message = "iam_role_name must be 1-64 characters from the set IAM accepts for a role name, or null to let the provider generate one."
  }
}
variable "iam_policy_arns" {
  type        = list(string)
  default     = ["arn:aws:iam::aws:policy/AdministratorAccess"]
  description = "IAM managed policy ARNs attached to the instance's role. AdministratorAccess as the _monolithic template attached it: this is a person's workbench rather than a controller, and rules.md A-5 exempts workbenches on purpose - the demo runs ECR, ECS, CodeDeploy, S3, SSM and git from this box. It also covers AmazonSSMManagedInstanceCore, which every association in the root needs. Scope it down for anything longer lived"

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
  description = "Optional absolute directory in which to write the bootstrap completion marker (touch <path>/userdata), for the associations that must not start until the bootstrap finished. When null, no marker is written and nothing downstream can wait on it (rules.md B-4/D-5)"

  validation {
    condition     = var.marker_file_path == null || can(regex("^/", var.marker_file_path))
    error_message = "marker_file_path must be an absolute path starting with '/', or null."
  }
}
variable "additional_user_data" {
  type        = string
  default     = ""
  description = "Shell script appended after code-server is started and before the completion marker is written. The root uses it to install docker and git, which is where the group change and the code-server restart belong (rules.md H-1)"

  validation {
    condition     = length(var.additional_user_data) < 12000
    error_message = "additional_user_data must stay under 12000 characters, leaving room for the base bootstrap script inside EC2's 16 KB user data limit."
  }
}
