variable "vpc_id" {
  type        = string
  description = "VPC the security group is created in. The spoke VPC - the instance has to sit behind the transit gateway for its traffic to be inspected at all"

  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must be a valid VPC ID (e.g. vpc-0123456789abcdef0)."
  }
}
variable "subnet_id" {
  type        = string
  description = <<-DESC
    Subnet the instance is launched in. A private subnet of the spoke VPC, and specifically the one in the
    availability zone whose NAT gateway address the project's checks compare against.

    This must not be a public subnet and must not be in the egress VPC. Either change gives the instance a
    path to the internet that does not pass the firewall, and every command this project publishes still
    succeeds - the curl returns an address, dnf works, the page loads - while nothing is inspected. The
    failure is that the demo proves nothing, and it reports no error while doing so.
  DESC

  validation {
    condition     = can(regex("^subnet-[0-9a-f]+$", var.subnet_id))
    error_message = "subnet_id must be a valid subnet ID (e.g. subnet-0123456789abcdef0)."
  }
}
variable "ami_id" {
  type        = string
  description = "AMI for the instance, resolved by the caller. Taken as an id rather than looked up here so the module does not need to know the caller reads it from an SSM public parameter (rules.md B-6), and so the lookup stays in the root where it is read at plan rather than deferred by this module's depends_on (rules.md D-6)"

  validation {
    condition     = can(regex("^ami-[0-9a-f]+$", var.ami_id))
    error_message = "ami_id must be a valid AMI ID (e.g. ami-0123456789abcdef0). An SSM parameter path passed here unresolved fails the plan rather than launching an instance from nothing."
  }
}
variable "key_name" {
  type        = string
  description = "Name of the EC2 key pair to attach. Close to decoration in this project - there is no internet gateway in this VPC, so there is no address to SSH to from outside and Session Manager is the way in - but a key pair cannot be added to a running instance afterwards without replacing it"

  validation {
    condition     = can(regex("^[ -~]{1,255}$", var.key_name))
    error_message = "key_name must be 1-255 printable ASCII characters."
  }
}
variable "instance_name" {
  type        = string
  default     = "app-bastion"
  description = "Name tag of the instance, as the _monolithic template tagged it. The tag is kept for continuity with the original; the module is named vscode_ec2 rather than bastion_ec2 because nothing connects through this host - see main.tf"

  validation {
    condition     = length(var.instance_name) > 0
    error_message = "instance_name must not be empty."
  }
}
variable "instance_type" {
  type        = string
  default     = "t3.medium"
  description = "Instance type, as the _monolithic template had it. Two vCPUs and 4 GiB, which is enough to run code-server plus a browser IDE session alongside the handful of dig and curl commands this project is about"

  validation {
    condition     = can(regex("^[a-z0-9]+[a-z0-9-]*\\.[a-z0-9]+$", var.instance_type))
    error_message = "instance_type must be a valid EC2 instance type (e.g. t3.medium)."
  }
}
variable "security_group_name" {
  type        = string
  default     = "app-bastion-sg"
  description = "Name of the security group. The _monolithic template created no security group at all and attached the spoke VPC's default group instead - see main.tf for why that substitution is the single most dangerous step in this conversion"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.security_group_name)) && !startswith(var.security_group_name, "sg-")
    error_message = "security_group_name must be 1-255 characters from the set AWS accepts for a security group name (a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*, no apostrophe) and must not start with \"sg-\", which EC2 reserves for security group IDs."
  }
}
variable "security_group_description" {
  type        = string
  default     = "Workbench in the spoke VPC, whose only route to the internet is the inspected egress path"
  description = "Description attached to the security group. Changing this value replaces the group, because AWS has no API to modify a security group description - and the instance is replaced with it (rules.md F-1). Note the deliberate absence of an apostrophe in the default: \"instance's\" would pass plan and fail the CreateSecurityGroup call at apply"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.security_group_description))
    error_message = "security_group_description must be 1-255 characters from the set AWS accepts for a security group description: a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*. An apostrophe is NOT allowed - EC2 rejects the CreateSecurityGroup call with InvalidParameterValue, which otherwise only surfaces at apply time (rules.md F-1)."
  }
}
variable "egress_cidr_blocks" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = <<-DESC
    Destinations the instance is allowed to reach outbound. An empty list creates no egress rule, which
    leaves the instance with no outbound access whatsoever.

    This is the variable to read twice in this module. The _monolithic template attached the VPC's default
    security group, which carries an allow-all egress rule, so the original had unrestricted egress without
    ever writing it down. A named group does not inherit that - see main.tf - and an empty list here
    reproduces the exact failure that rule F-2 exists for: apply succeeds, the instance reaches running,
    cloud-init cannot reach anything, code-server is never installed, and the one thing this project is
    built to demonstrate - traffic passing through a firewall - cannot happen because no traffic leaves.

    Narrowing it is legitimate and interesting here, because every destination in this list is reached
    through the firewall. 0.0.0.0/0 is the default because it is what the original had.
  DESC

  validation {
    condition     = alltrue([for cidr in var.egress_cidr_blocks : can(cidrhost(cidr, 0))])
    error_message = "egress_cidr_blocks must contain valid IPv4 CIDR blocks (e.g. 0.0.0.0/0)."
  }
}
variable "ingress_cidr_blocks" {
  type        = list(string)
  default     = []
  description = <<-DESC
    Source CIDRs allowed to reach code_server_port. Empty by default, and that is not an oversight.

    There is no inbound path into this VPC from outside: it has no internet gateway, and the transit
    gateway's only route sends traffic towards the egress VPC rather than accepting anything from it. The
    IDE is reached by forwarding a local port through Session Manager, and that connection is made by the
    SSM agent *on the instance* to its own loopback address - it never crosses the security group. So the
    group needs no inbound rule for the intended way in.

    Setting this is for reaching the IDE from somewhere else inside the two VPCs, in which case
    code_server_bind_address has to be widened to match or the listener will not accept the connection.
  DESC

  validation {
    condition     = alltrue([for cidr in var.ingress_cidr_blocks : can(cidrhost(cidr, 0))])
    error_message = "ingress_cidr_blocks must contain valid IPv4 CIDR blocks (e.g. 172.16.0.0/16)."
  }
}
variable "extra_security_group_ids" {
  type        = list(string)
  default     = []
  description = "Additional security group IDs attached to the instance, merged with the one this module creates. Here so a caller can add a group it owns without this module learning what it is for (rules.md B-6)"

  validation {
    condition     = alltrue([for id in var.extra_security_group_ids : can(regex("^sg-[0-9a-f]+$", id))])
    error_message = "extra_security_group_ids must contain valid security group IDs (e.g. sg-0123456789abcdef0)."
  }
}
variable "iam_policy_arns" {
  type        = list(string)
  default     = ["arn:aws:iam::aws:policy/AdministratorAccess"]
  description = <<-DESC
    Managed policy ARNs attached to the instance role.

    AdministratorAccess, which is what the _monolithic template attached, kept rather than narrowed. Two
    reasons, and the distinction between them matters because rules.md A-5 treats them differently.

    The original attached this policy itself, in Terraform, as a plain
    aws_iam_role_policy_attachment - it is not a case of a bootstrap script's narrow policy being
    replaced by a broad one during conversion. Narrowing it would therefore be a change to what the
    original did rather than a faithful translation.

    And this instance is a human workbench: a person opens code-server on it and runs the AWS CLI from its
    terminal to read firewall logs, describe route tables and search the transit gateway's routes. rules.md
    H-1 takes that position for vscode_ec2 and bastion_ec2, and A-5's audit excludes them for the same
    reason.

    What it must keep whatever else changes is SSM. Without AmazonSSMManagedInstanceCore or an equivalent
    the agent cannot register, which costs three separate things here: the README association never
    succeeds, Session Manager cannot open a shell, and the port forward that is the only way to the IDE
    does not exist.

    Note that the Lambda execution role from the original - which carried an inline ec2:* on "*" - is gone
    entirely, along with the function. That is a narrowing by deletion, and it is recorded in
    modules/transit_gateway/main.tf.
  DESC

  validation {
    condition     = length(var.iam_policy_arns) > 0 && alltrue([for arn in var.iam_policy_arns : can(regex("^arn:aws[a-z-]*:iam::", arn))])
    error_message = "iam_policy_arns must be a non-empty list of IAM policy ARNs. An empty list leaves the instance without SSM access, which means no README, no Session Manager shell and no way to reach the IDE."
  }
}
variable "code_server_port" {
  type        = number
  default     = 8000
  description = "Port code-server binds to. One value feeds the config file, the optional security group rule, the port forward command and the URL, so they cannot disagree (rules.md B-5)"

  validation {
    condition     = var.code_server_port > 0 && var.code_server_port <= 65535
    error_message = "code_server_port must be between 1 and 65535."
  }
}
variable "code_server_bind_address" {
  type        = string
  default     = "127.0.0.1"
  description = <<-DESC
    Address code-server listens on.

    Loopback by default, which is both safer and sufficient: the port forward that reaches this IDE is
    opened by the SSM agent on the instance connecting to its own loopback address, so nothing has to be
    reachable over the network. code-server here runs with authentication disabled, so a listener on
    0.0.0.0 would be an unauthenticated shell offered to anything that can route to the instance.

    0.0.0.0 is the setting to use together with ingress_cidr_blocks when the IDE should be reachable from
    elsewhere inside the two VPCs. Widening one without the other produces a connection that is refused
    (bind address too narrow) or one that times out (no ingress rule), and the two symptoms are easy to
    confuse.
  DESC

  validation {
    condition     = can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}$", var.code_server_bind_address))
    error_message = "code_server_bind_address must be an IPv4 address, typically 127.0.0.1 or 0.0.0.0. It is interpolated into the code-server configuration file written by the user data, so an arbitrary string would be an injection point."
  }
}
variable "code_server_version" {
  type        = string
  default     = "4.100.3"
  description = "code-server release to install. Pinned rather than resolved to latest: the download URL contains the version three times, and a floating version means an instance whose IDE differs depending on the day it was launched"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.code_server_version))
    error_message = "code_server_version must be a three-part version (e.g. 4.100.3), which is what the release tarball's name and directory both contain."
  }
}
variable "dnf_packages" {
  type        = list(string)
  default     = ["bind-utils", "wget", "tar", "gzip", "jq"]
  description = <<-DESC
    Packages installed before anything else runs.

    bind-utils is the _monolithic template's own choice and it is the only package the original installed,
    which says what the instance was for: dig and nslookup, to see the firewall's DNS rules take effect.
    wget, tar and gzip are named because the code-server install downloads and unpacks a tarball with them
    and a minimal Amazon Linux 2023 image does not guarantee wget. jq is for reading the AWS CLI output
    that the project's verification commands produce.

    Every one of these is fetched through the transit gateway, the firewall and a NAT gateway. A dnf step
    that times out is the first symptom of a broken egress chain, and /var/log/cloud-init-output.log is
    where it is visible.
  DESC

  validation {
    condition     = alltrue([for package in var.dnf_packages : can(regex("^[a-zA-Z0-9._+-]+$", package))])
    error_message = "dnf_packages entries must be plain package names - they are interpolated into a dnf command line."
  }
}
variable "timezone" {
  type        = string
  default     = "Asia/Seoul"
  description = "Timezone set on the instance. Worth keeping in mind when comparing the instance's own command output against the firewall's CloudWatch logs, which are always UTC"

  validation {
    condition     = can(regex("^[A-Za-z]+(/[A-Za-z0-9_+-]+)+$|^UTC$", var.timezone))
    error_message = "timezone must be a tz database name (e.g. Asia/Seoul) or UTC."
  }
}
variable "root_volume_size" {
  type        = number
  default     = 30
  description = "Root volume size in GiB. The _monolithic template set none, which means the AMI's own 8 GiB; 30 is the free-tier allowance and leaves room for the code-server install"

  validation {
    condition     = var.root_volume_size >= 8
    error_message = "root_volume_size must be at least 8 GiB, the size of the Amazon Linux 2023 root image."
  }
}
variable "root_volume_type" {
  type        = string
  default     = "gp3"
  description = "Root volume type. gp3 rather than the AMI default gp2 - same durability, lower price, and no reason to prefer gp2 for a new volume"

  validation {
    condition     = contains(["gp2", "gp3", "io1", "io2", "standard"], var.root_volume_type)
    error_message = "root_volume_type must be gp2, gp3, io1, io2 or standard."
  }
}
variable "root_volume_encrypted" {
  type        = bool
  default     = true
  description = "Whether the root volume is encrypted. The _monolithic template left this unset, which means unencrypted unless the account defaults otherwise"
}
variable "metadata_http_tokens" {
  type        = string
  default     = "required"
  description = "Whether IMDSv2 is enforced. Required, which is stricter than the _monolithic template's unset default of optional. Nothing on this instance reads the metadata service with an unsigned request - the SSM agent and the AWS CLI both handle the token themselves - and the instance role here is AdministratorAccess, so leaving IMDSv1 open is the one credential-theft path worth closing by default"

  validation {
    condition     = contains(["required", "optional"], var.metadata_http_tokens)
    error_message = "metadata_http_tokens must be required (IMDSv2 only) or optional (IMDSv1 allowed)."
  }
}
variable "additional_user_data" {
  type        = string
  default     = null
  description = "Extra shell appended after code-server is in place and before the marker file is written. Null adds nothing. Anything here runs before the marker the root's SSM association waits on, so a long step delays that association rather than racing it (rules.md B-4)"

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
    Directory a completion marker is written into as the very last act of the user data. Null writes no
    marker.

    The root's SSM association waits for <path>/userdata to appear before it writes anything, which is what
    orders it after the bootstrap rather than after the instance's create call returns (rules.md D-5). It
    is passed in and handed straight back out as an output so the path exists in exactly one place
    (rules.md B-5).

    The marker is written last on purpose. Writing it before additional_user_data would start the
    association while the install is still running.
  DESC

  validation {
    condition     = var.marker_file_path == null || can(regex("^/[^ ]*$", var.marker_file_path))
    error_message = "marker_file_path must be an absolute path with no spaces, or null to write no marker."
  }
}
variable "address_reflector_url" {
  type        = string
  default     = "https://ifconfig.me"
  description = "Service the egress check curls to learn which address its traffic left as. The answer should be one of the two NAT gateway Elastic IPs, which is what makes this a complete end-to-end test of the inspected path - and an address that is neither means traffic is leaving somewhere this project does not control"

  validation {
    condition     = can(regex("^https://[a-zA-Z0-9.-]+(/[^ ]*)?$", var.address_reflector_url))
    error_message = "address_reflector_url must be an https URL with no spaces - it is interpolated into a curl command published as an output."
  }
}
variable "blocked_resolver_address" {
  type        = string
  default     = "8.8.8.8"
  description = "Public resolver the DNS check queries, to show the firewall's stateful rules dropping it. Any address outside both VPCs works: what matters is that the query leaves the VPC, because a query to the Amazon resolver matches the local route and never reaches the firewall"

  validation {
    condition     = can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}$", var.blocked_resolver_address))
    error_message = "blocked_resolver_address must be an IPv4 address - it is interpolated into a dig command published as an output."
  }
}
variable "blocked_ping_address" {
  type        = string
  default     = "1.1.1.1"
  description = "Address the ICMP check pings, to show the stateless rule dropping it. The drop is silent rather than a rejection, so the expected result is a ping that reports 100% packet loss after its timeout"

  validation {
    condition     = can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}$", var.blocked_ping_address))
    error_message = "blocked_ping_address must be an IPv4 address - it is interpolated into a ping command published as an output."
  }
}
variable "dns_check_hostname" {
  type        = string
  default     = "amazon.com"
  description = "Hostname both DNS checks resolve. One query goes to the VPC resolver and should answer; the same query sent to blocked_resolver_address should hang. Running them side by side is what separates \"the firewall dropped it\" from \"DNS is broken\""

  validation {
    condition     = can(regex("^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$", var.dns_check_hostname))
    error_message = "dns_check_hostname must be a hostname - it is interpolated into dig commands published as outputs."
  }
}
