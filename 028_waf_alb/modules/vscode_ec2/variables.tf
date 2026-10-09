variable "vpc_id" {
  type        = string
  description = "VPC the security group is created in. Taken as an id so this module does not need to know how the caller found it (rules.md B-6)"

  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must be a valid VPC ID (e.g. vpc-0123456789abcdef0)."
  }
}
variable "subnet_id" {
  type        = string
  description = "Subnet the instance is launched in. Must be public: a browser reaches code-server on this host from outside the VPC, and the bootstrap pulls packages and the code-server tarball over the internet"

  validation {
    condition     = can(regex("^subnet-[0-9a-f]+$", var.subnet_id))
    error_message = "subnet_id must be a valid subnet ID (e.g. subnet-0123456789abcdef0)."
  }
}
variable "ami_id" {
  type        = string
  description = "AMI for the instance, resolved by the caller. An id rather than an SSM parameter path, so this module does not need to know where the caller read it from (rules.md B-6)"

  validation {
    condition     = can(regex("^ami-[0-9a-f]+$", var.ami_id))
    error_message = "ami_id must be a valid AMI ID (e.g. ami-0123456789abcdef0). An unresolved SSM parameter path passed here fails the plan rather than launching an instance from nothing."
  }
}
variable "key_name" {
  type        = string
  description = "Name of the EC2 key pair to attach. code-server in a browser is the intended way in; this is for the case where code-server never came up and cloud-init's output has to be read over SSH"

  validation {
    condition     = can(regex("^[ -~]{1,255}$", var.key_name))
    error_message = "key_name must be 1-255 printable ASCII characters."
  }
}
variable "instance_name" {
  type        = string
  default     = "bastion"
  description = "Name tag of the instance, as the _monolithic template tagged it. The tag is kept for continuity with the original even though nothing bastions through this host - see main.tf for why the module is not called bastion_ec2"

  validation {
    condition     = length(var.instance_name) > 0
    error_message = "instance_name must not be empty."
  }
}
variable "instance_type" {
  type        = string
  default     = "t3.small"
  description = "Instance type, as the _monolithic template had it. Enough for code-server plus a browser session and a handful of CLI calls, which is all this host does"

  validation {
    condition     = can(regex("^[a-z0-9]+[a-z0-9-]*\\.[a-z0-9]+$", var.instance_type))
    error_message = "instance_type must be a valid EC2 instance type (e.g. t3.small)."
  }
}
variable "security_group_name" {
  type        = string
  default     = null
  description = "Exact name for the security group. Null generates one from security_group_name_prefix, which is the default - the _monolithic template used the literal \"bastion-sg\", and a security group name has to be unique within a VPC, so a second copy of this project in the default VPC fails with InvalidGroup.Duplicate"

  validation {
    condition     = var.security_group_name == null || (can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.security_group_name)) && !startswith(var.security_group_name, "sg-"))
    error_message = "security_group_name must be 1-255 characters from the set AWS accepts for a security group name (a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*, no apostrophe) and must not start with \"sg-\", which EC2 reserves for security group IDs (rules.md F-1)."
  }
}
variable "security_group_name_prefix" {
  type        = string
  default     = "bastion-sg-"
  description = "Prefix for the generated security group name, used when security_group_name is null. Keeps the original's name recognisable while leaving room for a unique suffix"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,100}$", var.security_group_name_prefix))
    error_message = "security_group_name_prefix must be 1-100 characters from the set AWS accepts for a security group name, leaving room for the generated suffix."
  }
}
variable "security_group_description" {
  type        = string
  default     = "Security group for the code-server workbench the demo is driven from"
  description = "Description attached to the security group. The _monolithic template said \"Security Group for Bastion EC2 SSH Connection\", which described a use this host does not have. Changing this value replaces the group, because AWS has no API to modify a security group description (rules.md F-1)"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.security_group_description))
    error_message = "security_group_description must be 1-255 characters from the set AWS accepts for a security group description: a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*. An apostrophe is NOT allowed - EC2 rejects the CreateSecurityGroup call with InvalidParameterValue, which otherwise only surfaces at apply time (rules.md F-1)."
  }
}
variable "code_server_port" {
  type        = number
  default     = 8000
  description = "Port code-server binds to and the security group opens, as the _monolithic template had it. One value feeds the config file, the security group rule and the URL output, so they cannot disagree (rules.md B-5)"

  validation {
    condition     = var.code_server_port > 0 && var.code_server_port <= 65535
    error_message = "code_server_port must be between 1 and 65535."
  }
}
variable "code_server_version" {
  type        = string
  default     = "4.100.3"
  description = "code-server release to install, as the _monolithic template pinned it. Pinned rather than resolved to latest: the download URL contains the version three times, and a floating version means an IDE that differs depending on the day the project was applied"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.code_server_version))
    error_message = "code_server_version must be a three-part version (e.g. 4.100.3), which is what the release tarball's name and its directory both contain."
  }
}
variable "ssh_port" {
  type        = number
  default     = 22
  description = "Port the security group opens for SSH, as the _monolithic template opened it. Unlike 098_basic_lambda's copy of this module, the original here did open 22 rather than a port sshd was not listening on, so this value reproduces it"

  validation {
    condition     = var.ssh_port > 0 && var.ssh_port <= 65535
    error_message = "ssh_port must be between 1 and 65535."
  }
}
variable "ingress_cidr_blocks" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = <<-DESC
    Sources allowed to reach code_server_port and ssh_port. An empty list creates no ingress rule at all,
    which leaves the host reachable only through SSM Session Manager - workable, since the instance role
    carries the permissions for it, but then the IDE cannot be opened.

    0.0.0.0/0 is what the _monolithic template opened and it is the default here for continuity, but it
    deserves reading twice: code-server on this host runs with authentication disabled, so anyone who finds
    the address gets an editor and a shell as ec2-user on an instance whose role is AdministratorAccess. A
    real use narrows this to one address, and this project's own demo would still work - every command it
    publishes is run from this host or against public endpoints.
  DESC

  validation {
    condition     = alltrue([for cidr in var.ingress_cidr_blocks : can(cidrhost(cidr, 0))])
    error_message = "ingress_cidr_blocks must contain valid IPv4 CIDR blocks (e.g. 203.0.113.0/24)."
  }
}
variable "iam_policy_arns" {
  type        = list(string)
  default     = ["arn:aws:iam::aws:policy/AdministratorAccess"]
  description = <<-DESC
    Managed policy ARNs attached to this instance's role.

    AdministratorAccess, which is what the _monolithic template attached - and attached in Terraform rather
    than through a bootstrap script, so this is the second of the two cases rules.md A-5 distinguishes:
    there is no narrower policy hidden outside the template to recover. Narrowing it would be changing what
    the original did rather than reproducing it.

    It is kept broad because this host is a human workbench, which is the position rules.md H-1 takes for
    vscode_ec2 and bastion_ec2 and the reason A-5's audit excludes them. The automated host in this project
    - the app server - is narrowed to SSM access only, which is where that rule bites.

    Two things it has to keep whatever else changes. SSM permissions, because the root's association writes
    the README through them and without them that association waits for its timeout and writes nothing. And
    read access to wafv2, elasticloadbalancing, cloudwatch and ssm:GetParameter, which is what every command
    in that README needs.
  DESC

  validation {
    condition     = length(var.iam_policy_arns) > 0 && alltrue([for arn in var.iam_policy_arns : can(regex("^arn:aws[a-z-]*:iam::", arn))])
    error_message = "iam_policy_arns must be a non-empty list of IAM policy ARNs. An empty list leaves the instance without SSM access, which means the root's association hangs until its timeout and no README is written."
  }
}
variable "python_command" {
  type        = string
  default     = "python3.13"
  description = "Interpreter ensurepip is run against, named explicitly rather than reached through a symlink. The _monolithic template installed python3.13 and linked it to /usr/bin/python; see main.tf for why that link is not recreated. Nothing in this project's demo needs Python - the commands are curl and the AWS CLI - so this is here because the original installed it and because a workbench with a usable interpreter is worth more than the thirty seconds it costs"

  validation {
    condition     = can(regex("^python3(\\.[0-9]+)?$", var.python_command))
    error_message = "python_command must be python3 or python3.<minor> (e.g. python3.13). It is interpolated into a shell command line, so an arbitrary string here would be an injection point."
  }
}
variable "dnf_packages" {
  type        = list(string)
  default     = ["python3.13", "python3-pip", "wget", "tar", "gzip", "jq"]
  description = <<-DESC
    Packages installed with dnf.

    python3.13 and python3-pip are what the _monolithic template installed. wget, tar and gzip are named
    explicitly because the code-server install downloads and unpacks a tarball with them and a minimal
    Amazon Linux 2023 image is not guaranteed to carry wget.

    jq is an addition. Every verification command this project publishes returns JSON, and
    aws wafv2 get-sampled-requests in particular returns a nested structure in which the interesting part is
    one field per sample - without jq the answer to "did WAF block it" is several screens of output.
  DESC

  validation {
    condition     = alltrue([for package in var.dnf_packages : can(regex("^[a-zA-Z0-9._+-]+$", package))])
    error_message = "dnf_packages entries must be plain package names - they are interpolated into a dnf command line."
  }
}
variable "dnf_groups" {
  type        = list(string)
  default     = ["Development Tools"]
  description = "Package groups installed with dnf groupinstall, as the _monolithic template installed them. An empty list skips the step and takes several minutes off the boot; nothing this host does compiles anything, so the group is kept by default only because that is what the original did"

  validation {
    condition     = alltrue([for group in var.dnf_groups : can(regex("^[a-zA-Z0-9 ._+-]+$", group))])
    error_message = "dnf_groups entries must be plain group names - they are quoted and interpolated into a dnf command line."
  }
}
variable "timezone" {
  type        = string
  default     = "Asia/Seoul"
  description = "Timezone set on the instance, as the _monolithic template set it. Not purely cosmetic: the sampled-request and metric commands this project publishes build their time windows from this host's clock with date -u, so a wrong offset here would not break them but a reader comparing a local log timestamp against a UTC window needs to know which is which"

  validation {
    condition     = can(regex("^[A-Za-z]+(/[A-Za-z0-9_+-]+)+$|^UTC$", var.timezone))
    error_message = "timezone must be a tz database name (e.g. Asia/Seoul) or UTC."
  }
}
variable "associate_public_ip_address" {
  type        = bool
  default     = true
  description = "Whether the instance gets a public address, as the _monolithic template had it. Required twice over: a browser opens code-server on it, and in a default VPC - an internet gateway and no NAT gateway - an instance without one has no outbound route, so the bootstrap's dnf and wget calls time out"
}
variable "associate_elastic_ip" {
  type        = bool
  default     = false
  description = "Whether an Elastic IP is allocated and associated. False, as the _monolithic template had it. True is the right setting for a workbench that will be stopped and started, because the code-server URL is written into a README on the instance's own disk as well as into terraform output, and an auto-assigned address is released on stop - after which both copies point somewhere else (rules.md H-2)"
}
variable "additional_user_data" {
  type        = string
  default     = null
  description = "Extra shell appended after code-server is in place and before the marker file is written. Null adds nothing. Anything here runs before the marker, which is what the root's SSM association waits on, so a long step delays that association rather than racing it (rules.md B-4)"

  validation {
    # Null rather than "" is how to add nothing, which is what the template directive in main.tf tests. An
    # empty string renders a blank line and reads, in a plan, like a value someone meant to set.
    condition     = var.additional_user_data == null || length(trimspace(var.additional_user_data)) > 0
    error_message = "additional_user_data must be a non-empty script, or null to add nothing."
  }
}
variable "marker_file_path" {
  type        = string
  default     = null
  description = <<-DESC
    Directory a completion marker is written into as the very last act of the bootstrap. Null writes no
    marker.

    The root's SSM association waits for <path>/userdata to appear before writing the README, which is what
    orders it after the bootstrap rather than after the instance's create call returning (rules.md D-5). It
    is passed in and handed straight back out as an output so the path exists in exactly one place
    (rules.md B-5).

    The marker is written last on purpose. Written before the code-server install, the association would
    start while the IDE was still being unpacked and the README would land on a host that cannot open it.
  DESC

  validation {
    condition     = var.marker_file_path == null || can(regex("^/[^ ]*$", var.marker_file_path))
    error_message = "marker_file_path must be an absolute path with no spaces, or null to write no marker."
  }
}
variable "root_volume_size" {
  type        = number
  default     = 30
  description = "Root volume size in GiB. The _monolithic template set none, which means the AMI's own 8GiB; 30 is the free-tier allowance and leaves room for the Development Tools group and the code-server install"

  validation {
    condition     = var.root_volume_size >= 8
    error_message = "root_volume_size must be at least 8 GiB, the size of the Amazon Linux 2023 root image."
  }
}
variable "metadata_http_tokens" {
  type        = string
  default     = "required"
  description = "Whether IMDSv2 is enforced. required, where the _monolithic template left the provider default of optional. Nothing on this host reads the metadata service over IMDSv1 - the SSM agent and the AWS CLI handle the token themselves - and the alternative matters on this host in particular, because code-server runs here with authentication disabled"

  validation {
    condition     = contains(["required", "optional"], var.metadata_http_tokens)
    error_message = "metadata_http_tokens must be required (IMDSv2 only) or optional (IMDSv1 allowed)."
  }
}
