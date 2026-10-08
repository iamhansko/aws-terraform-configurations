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
  description = "Subnet the instance is launched in. Must be a public subnet: the instance is reached over RDP from outside the VPC and pulls the desktop and xrdp packages from the Ubuntu archives during cloud-init"

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
    error_message = "ami_id must be a valid AMI ID (e.g. ami-0123456789abcdef0)."
  }
}
variable "instance_name" {
  type        = string
  default     = "ubuntu"
  description = "Name tag for the instance"

  validation {
    condition     = length(var.instance_name) > 0
    error_message = "instance_name must not be empty."
  }
}
variable "instance_type" {
  type        = string
  default     = "m5.2xlarge"
  description = "Instance type, as the _monolithic template had it. A full GNOME desktop plus a Docker engine is the workload, and the desktop package set alone takes several minutes of CPU to unpack, so this is deliberately not a small type"

  validation {
    condition     = can(regex("^[a-z0-9]+[a-z0-9-]*\\.[a-z0-9]+$", var.instance_type))
    error_message = "instance_type must be a valid EC2 instance type (e.g. m5.2xlarge)."
  }
}
variable "key_name" {
  type        = string
  description = "Name of the EC2 key pair to attach. RDP is the intended way in, so this exists for the case where the desktop or xrdp fails to come up and the instance has to be inspected over SSH"

  validation {
    condition     = can(regex("^[ -~]{1,255}$", var.key_name))
    error_message = "key_name must be 1-255 printable ASCII characters."
  }
}
variable "associate_public_ip_address" {
  type        = bool
  default     = true
  description = "Whether the instance gets a public address. True: the RDP client connects to it from outside the VPC"
}
variable "password" {
  type        = string
  default     = "Rdp1234!"
  description = <<-DESC
    Password set for the ubuntu user, which is what the RDP login uses. xrdp authenticates through PAM
    against the local account, so there is no xrdp-specific credential store to populate.

    Not marked sensitive, and that is a deliberate trade for a demo: the root prints it as an output
    because a reader needs it to connect, and marking it sensitive would replace it with
    (sensitive value) there. Two consequences worth knowing. It is interpolated into user_data, which any
    process on the instance can read back from the instance metadata service, and it is stored in the
    Terraform state in clear. Neither is acceptable for anything but a throwaway desktop.
  DESC

  validation {
    # chpasswd reads "user:password" from a single line, so a newline in the value silently truncates it
    # and leaves a password nobody can guess - a login failure with no error anywhere to explain it.
    condition     = length(var.password) >= 8 && !can(regex("[\n\r:]", var.password))
    error_message = "password must be at least 8 characters and contain no newline or colon, because it is passed to chpasswd as a single user:password line."
  }
}
variable "rdp_port" {
  type        = number
  default     = 3389
  description = "Port xrdp listens on and the security group opens. 3389 is the default in the xrdp package shipped by Ubuntu; changing it here only changes the security group, so the xrdp configuration would have to be changed to match"

  validation {
    condition     = var.rdp_port > 0 && var.rdp_port <= 65535
    error_message = "rdp_port must be between 1 and 65535."
  }
}
variable "ingress_cidr_blocks" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = <<-DESC
    Source CIDRs allowed to reach rdp_port. An empty list creates no ingress rule at all, which leaves the
    instance reachable only through whatever else is attached to it.

    This replaces the _monolithic template's InboundFromAnywhere parameter, which was a string constrained
    to "True" and "False" because CloudFormation parameters have no boolean type. A list says the same
    thing and more: ["0.0.0.0/0"] is that parameter set to True, [] is False, and anything narrower is the
    case the string could not express. RDP exposed to the whole internet is the default only because that
    is what the template did - a real use narrows this.
  DESC

  validation {
    condition     = alltrue([for cidr in var.ingress_cidr_blocks : can(cidrhost(cidr, 0))])
    error_message = "ingress_cidr_blocks must contain valid IPv4 CIDR blocks (e.g. 203.0.113.0/24)."
  }
}
variable "security_group_name" {
  type        = string
  default     = "ubuntu-sg"
  description = "Name of the security group"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.security_group_name)) && !startswith(var.security_group_name, "sg-")
    error_message = "security_group_name must be 1-255 characters from the set AWS accepts for a security group name (a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*, no apostrophe) and must not start with \"sg-\", which EC2 reserves for security group IDs."
  }
}
variable "security_group_description" {
  type        = string
  default     = "Security group for the Ubuntu desktop instance reached over RDP"
  description = "Description attached to the security group. Changing it replaces the group, because AWS has no API to modify a security group description (rules.md F-1)"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.security_group_description))
    error_message = "security_group_description must be 1-255 characters from the set AWS accepts for a security group description: a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*. An apostrophe is NOT allowed - EC2 rejects the CreateSecurityGroup call with InvalidParameterValue, which otherwise only surfaces at apply time (rules.md F-1)."
  }
}
variable "iam_policy_arns" {
  type        = list(string)
  default     = ["arn:aws:iam::aws:policy/AdministratorAccess"]
  description = <<-DESC
    Managed policy ARNs attached to the instance role.

    AdministratorAccess, which is what the _monolithic template attached, and it is kept rather than
    narrowed. This instance is a human workbench: the desktop exists so a person can sit at it and run
    the AWS CLI, and the env.sh helper the userdata writes to the Desktop exists to hand them the
    instance role credentials. rules.md H-1 takes the same position for vscode_ec2 and bastion_ec2, and
    A-5 excludes those from its audit for this reason.

    Note that A-5's audit command filters on the names vscode_ec2 and bastion, so this module shows up in
    it as a finding. It is not one, and narrowing the policy here would be narrowing what the original
    could do rather than reproducing it.
  DESC

  validation {
    condition     = length(var.iam_policy_arns) > 0 && alltrue([for arn in var.iam_policy_arns : can(regex("^arn:aws[a-z-]*:iam::", arn))])
    error_message = "iam_policy_arns must be a non-empty list of IAM policy ARNs."
  }
}
variable "root_volume_size" {
  type        = number
  default     = 100
  description = "Root volume size in GiB, as the _monolithic template had it. The desktop package set, Docker images and a GNOME user profile are what fill it"

  validation {
    condition     = var.root_volume_size >= 8
    error_message = "root_volume_size must be at least 8 GiB to hold the Ubuntu desktop package set."
  }
}
variable "root_volume_type" {
  type        = string
  default     = "gp3"
  description = "Root volume type"

  validation {
    condition     = contains(["gp2", "gp3", "io1", "io2", "standard"], var.root_volume_type)
    error_message = "root_volume_type must be one of gp2, gp3, io1, io2, standard."
  }
}
variable "root_volume_encrypted" {
  type        = bool
  default     = false
  description = "Whether the root volume is encrypted. False reproduces the _monolithic template. True is the better default for anything holding real data, and costs nothing here"
}
variable "additional_user_data" {
  type        = string
  default     = null
  description = <<-DESC
    Extra shell injected into the userdata after xrdp is installed and before the desktop is installed.
    Null adds nothing.

    That position is not arbitrary and is the reason this is a variable rather than something a caller
    appends. Installing ubuntu-desktop takes the primary interface away from systemd-networkd and hands
    it to NetworkManager, which drops the link and DNS until the instance reboots, so anything that needs
    the network has to run before it (rules.md B-4 for the shape, main.tf for why the order matters).
  DESC
}
variable "reboot_delay_seconds" {
  type        = number
  default     = 30
  description = "How long the detached reboot waits before rebooting, giving cloud-init time to finish and record that it ran. Too short and the userdata runs again on the next boot; see main.tf"

  validation {
    condition     = var.reboot_delay_seconds >= 10
    error_message = "reboot_delay_seconds must be at least 10, so cloud-init can finish writing its semaphore before the instance goes down."
  }
}
