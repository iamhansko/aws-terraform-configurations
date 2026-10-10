variable "name" {
  type        = string
  default     = "bastion"
  description = "Name tag for the instance. \"bastion\" is the tag the _monolithic template set, and the module is named vscode_ec2 rather than bastion_ec2 because what it installs is code-server - the resource was called BastionEc2 but its cfn-init metadata was a workbench"
  validation {
    condition     = length(var.name) > 0
    error_message = "name must not be empty."
  }
}
variable "vpc_id" {
  type        = string
  description = "VPC ID the instance's security group is created in"
  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must be a valid VPC ID (e.g. vpc-0123456789abcdef0)."
  }
}
variable "subnet_id" {
  type        = string
  description = "Public subnet the instance is launched into. Public rather than private on purpose: the browser reaches code-server over its public address, and the image builds pull from public registries"
  validation {
    condition     = can(regex("^subnet-[0-9a-f]+$", var.subnet_id))
    error_message = "subnet_id must be a valid subnet ID (e.g. subnet-0123456789abcdef0)."
  }
}
variable "key_name" {
  type        = string
  default     = null
  description = "EC2 key pair name used to launch the instance. When null the instance is reachable only through SSM Session Manager"
  validation {
    condition     = var.key_name == null || can(regex("^[ -~]{1,255}$", var.key_name))
    error_message = "key_name must be 1-255 printable ASCII characters, or null."
  }
}
variable "instance_type" {
  type        = string
  default     = "t3.medium"
  description = <<-DESC
    EC2 instance type for the workbench.

    t3.medium where the _monolithic template said t3.small, and the reason is that the template never
    actually ran the work this instance now does. Its cfn-init calls failed, so nothing ever compiled
    anything on it. Here three Go programs are built in docker on this box, and one of them links
    aws-sdk-go-v2's DynamoDB client - a compile that wants well over a gigabyte on its own, next to a
    running code-server. On 2 GiB the Go linker is killed by the OOM killer, which surfaces as "signal:
    killed" in the build association's output and an empty ECR repository.
  DESC
  validation {
    condition     = can(regex("^[a-z0-9]+\\.[a-z0-9]+$", var.instance_type))
    error_message = "instance_type must be a valid EC2 instance type (e.g. t3.medium)."
  }
}
variable "ami_id" {
  type        = string
  description = "AMI for the instance. Resolved by the caller from the public SSM parameter the _monolithic template's BastionEc2AmiId pointed at, so this module takes an ami- id and does not have to know where it came from (rules.md B-6) - and so the parameter read stays out of a module that carries depends_on (rules.md D-6)"
  validation {
    condition     = can(regex("^ami-[0-9a-f]+$", var.ami_id))
    error_message = "ami_id must be a valid AMI ID (e.g. ami-0123456789abcdef0)."
  }
}
variable "root_volume_size" {
  type        = number
  default     = 40
  description = "Size in GiB of the root EBS volume. Larger than the AL2023 default because three multi-stage docker builds live here: a golang:alpine builder layer, an amazonlinux:2023 runtime layer and three built images, plus the build cache. A full disk shows up as a docker build failing to write a layer, with the repository left empty"
  validation {
    condition     = var.root_volume_size >= 8
    error_message = "root_volume_size must be at least 8 GiB."
  }
}
variable "code_server_version" {
  type        = string
  default     = "4.102.2"
  description = "code-server release version, as the _monolithic template's vscodeInstall config set pinned it"
  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.code_server_version))
    error_message = "code_server_version must be a semantic version (e.g. 4.102.2)."
  }
}
variable "code_server_port" {
  type        = number
  default     = 8000
  description = "Port code-server binds to, and the port opened in the security group. Re-exposed as an output so a caller building the URL reads one value (rules.md B-5)"
  validation {
    condition     = var.code_server_port > 0 && var.code_server_port <= 65535
    error_message = "code_server_port must be a valid TCP port."
  }
}
variable "python_version" {
  type        = string
  default     = "3.13"
  description = "Python minor version installed and symlinked to /usr/bin/python, as the pythonInstall config set's version env had it"
  validation {
    condition     = can(regex("^3\\.[0-9]+$", var.python_version))
    error_message = "python_version must be a Python 3 minor version (e.g. 3.13), which is appended to the dnf package name as python<version>."
  }
}
variable "timezone" {
  type        = string
  default     = "Asia/Seoul"
  description = "Timezone set with timedatectl, as the _monolithic template's userdata had it. It changes how timestamps read in the cloud-init log and in a shell on the instance, and nothing else"
  validation {
    condition     = can(regex("^[A-Za-z]+/[A-Za-z_+-]+$|^UTC$", var.timezone))
    error_message = "timezone must be a tz database name (e.g. Asia/Seoul) or UTC."
  }
}
variable "security_group_name" {
  type        = string
  default     = "bastion-sg"
  description = "Name of the security group created for the instance, as the _monolithic template named it"
  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.security_group_name)) && !startswith(var.security_group_name, "sg-")
    error_message = "security_group_name must be 1-255 characters from the set AWS accepts for a security group name (a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*, no apostrophe) and must not start with \"sg-\", which EC2 reserves for security group IDs."
  }
}
variable "security_group_description" {
  type        = string
  default     = "Security Group for Bastion EC2"
  description = "Description attached to the security group, as the _monolithic template had it. Changing it replaces the group, because AWS has no API to modify a group description (rules.md F-1)"
  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.security_group_description))
    error_message = "security_group_description must be 1-255 characters from the set AWS accepts for a security group description: a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*. An apostrophe is NOT allowed - EC2 rejects CreateSecurityGroup with InvalidParameterValue, which otherwise only surfaces part-way through apply (rules.md F-1)."
  }
}
variable "allow_inbound_from_anywhere" {
  type        = bool
  default     = true
  description = "Whether to open code_server_port to 0.0.0.0/0, as the _monolithic template did. Note what that exposes: code-server is configured with auth: none and cert: false, so anyone who finds the address gets an unauthenticated root-capable shell on an instance holding AdministratorAccess. It is the demo's only way in and it is reproduced, but it is not something to leave running - set this false and reach the port through SSM Session Manager port forwarding instead"
}
variable "ssh_ingress_cidr_blocks" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = "CIDR blocks allowed inbound on port 22, as the _monolithic template's second ingress block had it. Empty disables SSH entirely; the instance role carries AmazonSSMManagedInstanceCore either way, so Session Manager still works"
  validation {
    condition     = alltrue([for cidr in var.ssh_ingress_cidr_blocks : can(cidrhost(cidr, 0))])
    error_message = "ssh_ingress_cidr_blocks must contain valid IPv4 CIDR blocks."
  }
}
variable "associate_public_ip_address" {
  type        = bool
  default     = true
  description = "Whether to associate a public IPv4 address with the instance, as the _monolithic template did"
}
variable "iam_policy_arns" {
  type        = list(string)
  default     = ["arn:aws:iam::aws:policy/AdministratorAccess"]
  description = <<-DESC
    Managed policy ARNs on the instance role.

    AdministratorAccess, as the _monolithic template attached. Kept, and rules.md A-5 is the reason rather
    than an exception to it: this is a person's workbench, not a controller-shaped principal. It is where
    the demo is driven from, and the work it does is wide - ECR login and push, Secrets Manager reads,
    MySQL schema creation, ECS describe calls and whatever the reader types next. It also covers
    AmazonSSMManagedInstanceCore, which every association in this project needs.

    The ECS task role is the other AdministratorAccess in the template and that one is not a workbench, so
    it is narrowed instead - see modules/ecs_task_iam_roles.
  DESC
  validation {
    condition     = alltrue([for arn in var.iam_policy_arns : can(regex("^arn:aws:iam::", arn))])
    error_message = "iam_policy_arns must contain valid IAM policy ARNs."
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
variable "marker_file_path" {
  type        = string
  default     = null
  description = "Absolute directory in which to create the userdata completion marker (touch <path>/userdata), for the SSM associations that must not start until the bootstrap finished. When null, no marker is created and nothing downstream can order itself (rules.md B-4, D-5)"
  validation {
    condition     = var.marker_file_path == null || can(regex("^/", var.marker_file_path))
    error_message = "marker_file_path must be an absolute path starting with '/', or null."
  }
}
variable "additional_user_data" {
  type        = string
  default     = ""
  description = "Shell appended after code-server is running and before the completion marker is written. This is where the caller installs docker and the mysql client, because the module must not need to know that its root builds container images (rules.md H-1)"
  validation {
    condition     = length(var.additional_user_data) < 8000
    error_message = "additional_user_data must stay under 8000 characters, leaving room for the base bootstrap inside EC2's 16 KB user data limit. Application sources do not belong here - they are written by the SSM associations in the root instead."
  }
}
