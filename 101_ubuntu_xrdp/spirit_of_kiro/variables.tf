variable "aws_region" {
  type        = string
  default     = null
  description = "Region to deploy into. Null follows the provider chain (AWS_REGION / AWS_DEFAULT_REGION), which is how the _monolithic template was run"

  validation {
    condition     = var.aws_region == null || can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "aws_region must be a region code such as us-east-1, or null to follow the provider chain."
  }
}
variable "project_name" {
  type        = string
  default     = "spirit-of-kiro"
  description = "Prefix for the Name tags and generated names of everything in this root, so a second copy in one account stays tellable apart"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,30}$", var.project_name))
    error_message = "project_name must be 2-31 characters of lowercase letters, digits and hyphens."
  }
}
variable "ami_ssm_parameter_name" {
  type        = string
  default     = "/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id"
  description = "Public SSM parameter holding the AMI id, as the _monolithic template had it. Canonical publishes these per release and architecture, so the region never has to be mapped to an AMI id by hand"

  validation {
    condition     = startswith(var.ami_ssm_parameter_name, "/aws/service/canonical/ubuntu/")
    error_message = "ami_ssm_parameter_name must be a Canonical Ubuntu public parameter path under /aws/service/canonical/ubuntu/."
  }
}
variable "vpc_cidr_block" {
  type        = string
  default     = "10.0.0.0/16"
  description = "CIDR block for the VPC"

  validation {
    condition     = can(cidrhost(var.vpc_cidr_block, 0))
    error_message = "vpc_cidr_block must be a valid IPv4 CIDR block (e.g. 10.0.0.0/16)."
  }
}
variable "instance_type" {
  type        = string
  default     = "m5.2xlarge"
  description = "Instance type for the desktop. This variant also builds and runs the application the repository below checks out, on top of the desktop and Docker, so it is the heavier of the two variants"

  validation {
    condition     = can(regex("^[a-z0-9]+[a-z0-9-]*\\.[a-z0-9]+$", var.instance_type))
    error_message = "instance_type must be a valid EC2 instance type (e.g. m5.2xlarge)."
  }
}
variable "password" {
  type        = string
  default     = "Rdp1234!"
  description = "Password set on the ubuntu account, which is what the RDP login uses. See the ubuntu_ec2 module variable for why this is not marked sensitive and what that exposes"

  validation {
    condition     = length(var.password) >= 8 && !can(regex("[\n\r:]", var.password))
    error_message = "password must be at least 8 characters and contain no newline or colon, because it is passed to chpasswd as a single user:password line."
  }
}
variable "rdp_ingress_cidr_blocks" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = "Source CIDRs allowed to reach RDP. The default is the whole internet because that is what the _monolithic template's InboundFromAnywhere parameter defaulted to; narrowing it to the address you connect from is the single most useful change to make here. An empty list creates no ingress rule"

  validation {
    condition     = alltrue([for cidr in var.rdp_ingress_cidr_blocks : can(cidrhost(cidr, 0))])
    error_message = "rdp_ingress_cidr_blocks must contain valid IPv4 CIDR blocks (e.g. 203.0.113.0/24)."
  }
}
variable "root_volume_size" {
  type        = number
  default     = 100
  description = "Root volume size in GiB"

  validation {
    condition     = var.root_volume_size >= 8
    error_message = "root_volume_size must be at least 8 GiB to hold the Ubuntu desktop package set."
  }
}
variable "application_repository_url" {
  type        = string
  default     = "https://github.com/iamhansko/spirit-of-kiro"
  description = "Repository cloned onto the desktop and built by its own scripts/init.sh. This is what makes this variant different from ubuntu_24_04, which installs the same desktop and stops there"

  validation {
    condition     = can(regex("^https://", var.application_repository_url))
    error_message = "application_repository_url must be an https URL, because the clone runs unattended in cloud-init with no SSH key available to it."
  }
}
variable "application_repository_ref" {
  type        = string
  default     = "linux"
  description = "Branch or tag checked out after the clone, as the _monolithic template had it. A branch name tracks whatever it points at, so a build that worked yesterday can fail today - pin a tag or commit to make the apply reproducible"

  validation {
    condition     = length(var.application_repository_ref) > 0
    error_message = "application_repository_ref must not be empty."
  }
}
variable "kiro_install_script_url" {
  type        = string
  default     = "https://raw.githubusercontent.com/abhilashiig/kiro-ide-linux-installation/main/clone-and-install-kiro.sh"
  description = <<-DESC
    Installer for the Kiro IDE, fetched and piped into a root shell during cloud-init, which is what the
    _monolithic template did. Null skips it.

    Worth being explicit about what this is: a third-party script from a personal repository, on a branch
    rather than a tag, executed as root with no checksum. Whatever that URL serves at apply time is what
    runs. It is a variable rather than a literal so it is visible here and can be pointed at a pinned
    copy, and nullable so a root that does not want it does not have to edit the userdata.
  DESC

  validation {
    condition     = var.kiro_install_script_url == null || can(regex("^https://", var.kiro_install_script_url))
    error_message = "kiro_install_script_url must be an https URL, or null to skip the installer."
  }
}
