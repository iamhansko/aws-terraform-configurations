variable "vpc_id" {
  type        = string
  description = "VPC the security group is created in"

  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must be a valid VPC ID (e.g. vpc-0123456789abcdef0)."
  }
}
variable "subnet_id" {
  type        = string
  description = "Subnet the instance is launched in. Must be a public subnet: a browser reaches code-server on this instance from outside the VPC, and cloud-init pulls packages, the code-server tarball and PyPI wheels over the internet"

  validation {
    condition     = can(regex("^subnet-[0-9a-f]+$", var.subnet_id))
    error_message = "subnet_id must be a valid subnet ID (e.g. subnet-0123456789abcdef0)."
  }
}
variable "ami_id" {
  type        = string
  description = "AMI for the instance, resolved by the caller. Taken as an id rather than looked up here so the module does not need to know that the caller reads it from an SSM public parameter (rules.md B-6)"

  validation {
    condition     = can(regex("^ami-[0-9a-f]+$", var.ami_id))
    error_message = "ami_id must be a valid AMI ID (e.g. ami-0123456789abcdef0). An SSM parameter path passed here unresolved fails the plan rather than launching an instance from nothing."
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
  default     = "queue-bastion"
  description = "Name tag of the instance, as the _monolithic template tagged it. The name is kept for continuity with the original even though nothing connects through this host - see main.tf on why the module is not called bastion_ec2"

  validation {
    condition     = length(var.instance_name) > 0
    error_message = "instance_name must not be empty."
  }
}
variable "instance_type" {
  type        = string
  default     = "t3.small"
  description = "Instance type, as the _monolithic template had it. The load generator is network-bound rather than CPU-bound - it holds a few hundred open sockets and waits - so a small type is enough, but note that code-server, a browser IDE and the generator share two vCPUs"

  validation {
    condition     = can(regex("^[a-z0-9]+[a-z0-9-]*\\.[a-z0-9]+$", var.instance_type))
    error_message = "instance_type must be a valid EC2 instance type (e.g. t3.small)."
  }
}
variable "security_group_name" {
  type        = string
  default     = "bastion-ec2-sg"
  description = "Name of the security group, matching the Name tag the _monolithic template used"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.security_group_name)) && !startswith(var.security_group_name, "sg-")
    error_message = "security_group_name must be 1-255 characters from the set AWS accepts for a security group name (a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*, no apostrophe) and must not start with \"sg-\", which EC2 reserves for security group IDs."
  }
}
variable "security_group_description" {
  type        = string
  default     = "Security group for the code-server workbench that drives the load generator"
  description = "Description attached to the security group. The _monolithic template said only \"Security Group\". Changing this value replaces the group, because AWS has no API to modify a security group description (rules.md F-1)"

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
  description = "code-server release to install, as the _monolithic template pinned it. Pinned rather than resolved to latest: the download URL contains the version three times, and a floating version would mean an instance whose IDE differs depending on the day it was launched"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.code_server_version))
    error_message = "code_server_version must be a three-part version (e.g. 4.100.3), which is what the release tarball's name and directory both contain."
  }
}
variable "ssh_port" {
  type        = number
  default     = 22
  description = <<-DESC
    Port the security group opens for SSH.

    22, where the _monolithic template opened 2222. That rule admitted nothing: sshd on Amazon Linux 2023
    listens on 22 and no line of the template's user data changed its Port directive, so the group opened a
    port with nothing behind it while the port that was actually listening stayed closed. The symptom is a
    connection that times out with a key pair and a private key that are both perfectly good.

    Opening 2222 instead is still expressible, and it needs an sshd configuration line in
    additional_user_data to go with it.
  DESC

  validation {
    condition     = var.ssh_port > 0 && var.ssh_port <= 65535
    error_message = "ssh_port must be between 1 and 65535."
  }
}
variable "ingress_cidr_blocks" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = <<-DESC
    Source CIDRs allowed to reach code_server_port and ssh_port. An empty list creates no ingress rules at
    all, which leaves the instance reachable only through SSM Session Manager.

    0.0.0.0/0 is what the _monolithic template opened, and it is the default here for the same reason, but it
    deserves to be read twice: code-server on this instance runs with auth disabled, so anyone who finds the
    address gets a root-capable editor and shell on a host whose instance role is AdministratorAccess. A real
    use narrows this to one address.
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
    Managed policy ARNs attached to the instance role.

    AdministratorAccess, which is what the _monolithic template attached, kept rather than narrowed. This
    instance is a human workbench: a person opens code-server on it and runs the AWS CLI and the load
    generator from its terminal. rules.md H-1 takes the same position for vscode_ec2 and bastion_ec2, and A-5
    excludes those from its audit for exactly this reason.

    Two things it has to keep whatever else changes. ssm:* so the SSM associations in the root can run on it -
    without AmazonSSMManagedInstanceCore or an equivalent, those associations never report success and the
    README is never written. And lambda:GetFunctionUrlConfig, which is how the generator finds the endpoint.
  DESC

  validation {
    condition     = length(var.iam_policy_arns) > 0 && alltrue([for arn in var.iam_policy_arns : can(regex("^arn:aws[a-z-]*:iam::", arn))])
    error_message = "iam_policy_arns must be a non-empty list of IAM policy ARNs. An empty list leaves the instance without SSM access, which means the root's associations hang until their timeout and no README is written."
  }
}
variable "python_command" {
  type        = string
  default     = "python3"
  description = <<-DESC
    Interpreter used to install the generator's dependencies and to run it.

    python3, which on Amazon Linux 2023 is the distribution's own 3.9, and the reason is worth setting out
    because the _monolithic template looks like it decided otherwise. It installed python3.13 and then ran
    "ln -s /usr/bin/python3.13 /usr/bin/python3", which fails with "File exists" - /usr/bin/python3 is already
    a symlink managed by the distribution. The link was never created, so pip installed aiohttp and boto3 into
    3.9 and the generator ran on 3.9, and the whole thing worked by accident.

    Forcing that link with -f is the one repair not to make. dnf itself is a Python program whose modules are
    installed for the system interpreter, so repointing python3 at 3.13 breaks every later dnf call - on the
    worker instance, where a dnf install follows that line, it would mean the CloudWatch agent is never
    installed and therefore no log group, no metric and no demo.

    python3.13 is installed and usable by name, so setting this to python3.13 is supported and the packages
    then land there instead.
  DESC

  validation {
    condition     = can(regex("^python3(\\.[0-9]+)?$", var.python_command))
    error_message = "python_command must be python3 or python3.<minor> (e.g. python3.13). It is interpolated into shell commands in the user data, so an arbitrary string here would be an injection point."
  }
}
variable "python_packages" {
  type        = list(string)
  default     = ["python3.13", "wget", "tar", "gzip"]
  description = "Packages installed with dnf before anything else runs. python3.13 is what the _monolithic template installed; wget, tar and gzip are named explicitly because the code-server install downloads and unpacks a tarball with them and a minimal AL2023 image is not guaranteed to carry wget"

  validation {
    condition     = alltrue([for package in var.python_packages : can(regex("^[a-zA-Z0-9._+-]+$", package))])
    error_message = "python_packages entries must be plain package names - they are interpolated into a dnf command line."
  }
}
variable "pip_packages" {
  type        = list(string)
  default     = ["aiohttp", "boto3", "requests"]
  description = "Python packages the load generator imports. aiohttp drives the concurrent POSTs, boto3 resolves the function URL by name, and requests reads the instance identity document to discover the region - all three are imported at the top of the generator, so a missing one is an ImportError the moment it is run"

  validation {
    condition     = alltrue([for package in var.pip_packages : can(regex("^[a-zA-Z0-9._\\[\\]=<>!-]+$", package))])
    error_message = "pip_packages entries must be plain requirement specifiers - they are interpolated into a pip command line."
  }
}
variable "load_generator_script" {
  type        = string
  default     = null
  description = <<-DESC
    Body of the load generator, rendered by the caller and written to load_generator_path on first boot. Null
    writes no script.

    Passed in rather than templated here because the root renders it once and uses it twice - here, and again
    in the SSM association that rewrites it on later applies (rules.md B-5). User data runs exactly once per
    instance, so without that association a change to the generator's sizing would update Terraform state and
    leave the file on a running instance at its first-boot contents, with the plan reporting an in-place
    update that never reached the disk.
  DESC

  validation {
    condition     = var.load_generator_script == null || length(var.load_generator_script) > 0
    error_message = "load_generator_script must be a non-empty script, or null to write no script. An empty string produces an empty file, which fails at run time with nothing to explain it."
  }
  validation {
    # The body goes into a quoted heredoc whose terminator is TFLOADGEN. A line in the script equal to that
    # word would end the heredoc early, and the rest of the script would be executed as shell - which is
    # neither a plan error nor an apply error, just an instance whose bootstrap did something unintended.
    condition     = var.load_generator_script == null || !can(regex("(?m)^TFLOADGEN\\s*$", var.load_generator_script))
    error_message = "load_generator_script must not contain a line consisting of TFLOADGEN, which is the heredoc terminator the user data writes it with - such a line would close the heredoc early and the remainder of the script would be run as shell commands."
  }
}
variable "load_generator_path" {
  type        = string
  default     = "/home/ec2-user/message-app.py"
  description = "Absolute path the generator is written to. Re-exposed as an output so the root's association and the run command it publishes both read one value (rules.md B-5)"

  validation {
    condition     = can(regex("^/[^ ]*$", var.load_generator_path))
    error_message = "load_generator_path must be an absolute path with no spaces - it is interpolated into shell redirections and a chown in the user data."
  }
}
variable "timezone" {
  type        = string
  default     = "Asia/Seoul"
  description = "Timezone set on the instance, as the _monolithic template set it. It is not cosmetic here: the worker's log lines are timestamped by the local clock, so this is the offset to keep in mind when comparing them against a CloudWatch metric, which is always UTC"

  validation {
    condition     = can(regex("^[A-Za-z]+(/[A-Za-z0-9_+-]+)+$|^UTC$", var.timezone))
    error_message = "timezone must be a tz database name (e.g. Asia/Seoul) or UTC."
  }
}
variable "associate_elastic_ip" {
  type        = bool
  default     = true
  description = "Whether an Elastic IP is allocated and associated, as the _monolithic template did. True matters because the code-server URL is written into a README on the instance and printed as an output: an auto-assigned public address changes on every stop/start, which would leave both pointing somewhere else"
}
variable "additional_user_data" {
  type        = string
  default     = null
  description = "Extra shell appended after code-server and the generator are in place and before the marker file is written. Null adds nothing. Anything here runs before the marker, which is what the root's SSM associations wait on, so a long step delays them rather than racing them (rules.md B-4)"

  validation {
    # Null rather than "" is the way to add nothing, which is what the template directive in main.tf tests.
    # An empty string renders a blank line and reads, in a plan, like a value someone meant to set.
    condition     = var.additional_user_data == null || length(trimspace(var.additional_user_data)) > 0
    error_message = "additional_user_data must be a non-empty script, or null to add nothing."
  }
}
variable "marker_file_path" {
  type        = string
  default     = null
  description = <<-DESC
    Directory a completion marker is written into as the very last act of the user data. Null writes no marker.

    The root's SSM associations wait for <path>/userdata to appear before they do anything, which is what
    orders them after the bootstrap rather than after the instance's create call (rules.md D-5). It is passed
    in and handed straight back out as an output so the path exists in exactly one place (rules.md B-5).

    The marker is written last on purpose. Writing it before additional_user_data would start the associations
    while pip is still installing, and the README would land on an instance that has no generator to run.
  DESC

  validation {
    condition     = var.marker_file_path == null || can(regex("^/[^ ]*$", var.marker_file_path))
    error_message = "marker_file_path must be an absolute path with no spaces, or null to write no marker."
  }
}
variable "root_volume_size" {
  type        = number
  default     = 30
  description = "Root volume size in GiB. The _monolithic template set none, which means the AMI's own 8GiB; 30 is the free-tier allowance and leaves room for the Development Tools group, the code-server install and a pip cache"

  validation {
    condition     = var.root_volume_size >= 8
    error_message = "root_volume_size must be at least 8 GiB, the size of the Amazon Linux 2023 root image."
  }
}
variable "metadata_http_tokens" {
  type        = string
  default     = "optional"
  description = <<-DESC
    Whether IMDSv2 is enforced. Optional, as the _monolithic template set it, and this is the one place in
    this module where the weaker setting is kept deliberately.

    The load generator discovers its region by asking the metadata service for
    /latest/dynamic/instance-identity/document with a plain requests.get and no token - that is an IMDSv1
    request. Enforcing v2 makes it return 401, the generator catches it and raises
    "리전 메타데이터 조회 실패", and the whole load run stops before it sends anything. Nothing else on this
    instance reads metadata directly; boto3 and the SSM agent both handle the token themselves.

    So required is the better setting and it costs one line in the generator: replacing that request with
    boto3.session.Session().region_name, which gets the same answer through the SDK. Until that changes, this
    stays optional, which means a process or an SSRF on this host can read the instance role's credentials -
    on a host whose code-server has authentication disabled and whose role is AdministratorAccess.
  DESC

  validation {
    condition     = contains(["required", "optional"], var.metadata_http_tokens)
    error_message = "metadata_http_tokens must be required (IMDSv2 only) or optional (IMDSv1 allowed)."
  }
}
