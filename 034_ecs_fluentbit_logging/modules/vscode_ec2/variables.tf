variable "name" {
  type        = string
  default     = "logging-bastion"
  description = "Name tag for the instance and its elastic IP, as the _monolithic template tagged it"
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
  description = "Public subnet ID the instance is launched into. It has to be a public one: this VPC has no NAT gateway, so an instance on a subnet without a route to the internet gateway cannot download code-server or push an image"
  validation {
    condition     = can(regex("^subnet-[0-9a-f]+$", var.subnet_id))
    error_message = "subnet_id must be a valid subnet ID (e.g. subnet-0123456789abcdef0)."
  }
}
variable "ami_id" {
  type        = string
  description = "AMI ID for the instance. Resolved from an SSM public parameter by the root rather than by this module, so the read happens at plan time rather than being deferred to apply by the module's depends_on (rules.md D-6)"
  validation {
    condition     = can(regex("^ami-[0-9a-f]+$", var.ami_id))
    error_message = "ami_id must be a valid AMI ID (e.g. ami-0123456789abcdef0)."
  }
}
variable "key_name" {
  type        = string
  default     = null
  description = "Optional EC2 key pair name used to launch the instance. When null, the instance is reachable only through code-server and SSM Session Manager"
  validation {
    condition     = var.key_name == null || can(regex("^[ -~]{1,255}$", var.key_name))
    error_message = "key_name must be a string of printable ASCII characters (255 or fewer), or null."
  }
}
variable "instance_type" {
  type        = string
  default     = "t3.small"
  description = <<-DESC
    EC2 instance type for the workbench.
    The _monolithic template used t3.micro. This is one size up, because of what the root then asks this
    box to do: code-server is resident, and on top of it a docker daemon builds the application image and
    pulls the Fluent Bit image. On t3.micro's 1 GiB that puts code-server and dockerd in competition for
    memory, and when the OOM killer resolves it the visible symptom is an SSM association that fails
    partway through the build with no explanation in its own output.
    t3.micro still works if the build is the only thing running; this trades a few cents for not having
    to know that.
  DESC
  validation {
    condition     = can(regex("^[a-z0-9]+\\.[a-z0-9]+$", var.instance_type))
    error_message = "instance_type must be a valid EC2 instance type (e.g. t3.small)."
  }
}
variable "root_volume_size" {
  type        = number
  default     = 30
  description = "Size in GiB of the instance's root EBS volume. The _monolithic template declared none and took the AMI's default 8 GiB, which this project then fills: the python base image, the aws-for-fluent-bit image and both built images all land on this disk, and a build that runs out of space fails inside the SSM association rather than anywhere Terraform reports"
  validation {
    condition     = var.root_volume_size >= 8
    error_message = "root_volume_size must be at least 8 GiB."
  }
}
variable "code_server_version" {
  type        = string
  default     = "4.100.3"
  description = "code-server release version to install, as the _monolithic template pinned it"
  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.code_server_version))
    error_message = "code_server_version must be a semantic version (e.g. 4.100.3)."
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
  default     = "bastion-ec2-sg"
  description = "Name of the security group created for the instance, as the _monolithic template tagged it"
  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.security_group_name)) && !startswith(var.security_group_name, "sg-")
    error_message = "security_group_name must be 1-255 characters from the set AWS accepts for a security group name (a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*, no apostrophe) and must not start with \"sg-\", which EC2 reserves for security group IDs."
  }
}
variable "security_group_description" {
  type        = string
  default     = "Security group for the code-server workbench instance"
  description = "Description attached to the security group. Changing it replaces the group, because AWS has no API for editing a group description (rules.md F-1)"
  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.security_group_description))
    error_message = "security_group_description must be 1-255 characters from the set AWS accepts for a security group description: a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*. An apostrophe is NOT allowed - EC2 rejects CreateSecurityGroup with InvalidParameterValue, which otherwise only surfaces at apply time (rules.md F-1)."
  }
}
variable "allow_inbound_from_anywhere" {
  type        = bool
  default     = true
  description = "Whether to allow inbound access to code_server_port from 0.0.0.0/0, as the _monolithic template did. code-server runs with auth: none, so while this is true the URL in the outputs is the only credential there is. Set it false and reach code-server over SSM Session Manager port forwarding instead"
}
variable "ssh_ingress_cidr_blocks" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = "Source CIDR blocks allowed inbound on port 22, which is what the _monolithic template opened. An empty list closes SSH; the instance is still reachable over SSM Session Manager"
  validation {
    condition     = alltrue([for cidr in var.ssh_ingress_cidr_blocks : can(cidrhost(cidr, 0))])
    error_message = "ssh_ingress_cidr_blocks must contain valid IPv4 CIDR blocks (e.g. 203.0.113.4/32), or be empty."
  }
}
variable "associate_public_ip_address" {
  type        = bool
  default     = true
  description = "Whether to associate a public IP address with the instance at launch. The elastic IP replaces it afterwards, but the launch-time address is what cloud-init uses to reach dnf and GitHub"
}
variable "iam_policy_arns" {
  type        = list(string)
  default     = ["arn:aws:iam::aws:policy/AdministratorAccess"]
  description = "IAM managed policy ARNs attached to the instance's IAM role. AdministratorAccess is what the _monolithic template attached and it is kept: this is a person's workbench rather than a controller, so breadth here is the intent rather than an oversight (rules.md A-5). It also covers what the root's SSM associations need - AmazonSSMManagedInstanceCore to be driven at all, and ECR push for the image build"
  validation {
    condition     = length(var.iam_policy_arns) > 0 && alltrue([for arn in var.iam_policy_arns : can(regex("^arn:aws[a-z-]*:iam::", arn))])
    error_message = "iam_policy_arns must be a non-empty list of IAM policy ARNs. Without at least AmazonSSMManagedInstanceCore the instance never registers with Systems Manager, and every association in the root hangs until its timeout."
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
  description = "Optional absolute directory in which to create a userdata completion marker file (touch <path>/userdata), for SSM associations that must wait until the bootstrap finished. When null, no marker file is created (rules.md B-4)"
  validation {
    condition     = var.marker_file_path == null || can(regex("^/", var.marker_file_path))
    error_message = "marker_file_path must be an absolute path starting with '/', or null."
  }
}
variable "additional_user_data" {
  type        = string
  default     = ""
  description = "Additional shell script content appended after code-server is started and before the completion marker is written. This is where docker is installed, because the module must not have to know that its root also builds container images (rules.md H-1)"
  validation {
    condition     = length(var.additional_user_data) < 12000
    error_message = "additional_user_data must stay under 12000 characters, leaving room for the base bootstrap script inside EC2's 16 KB user data limit."
  }
}
