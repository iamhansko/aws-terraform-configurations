variable "aws_region" {
  type        = string
  default     = null
  description = "Region to deploy into. Null follows the provider chain (AWS_REGION / AWS_DEFAULT_REGION), which is how the _monolithic template was run"

  validation {
    condition     = var.aws_region == null || can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "aws_region must be a region code such as ap-northeast-2, or null to follow the provider chain."
  }
}
variable "project_name" {
  type        = string
  default     = "ubuntu-xrdp"
  description = "Prefix for the Name tags and generated names of everything in this root, so a second copy in one account stays tellable apart"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,30}$", var.project_name))
    error_message = "project_name must be 2-31 characters of lowercase letters, digits and hyphens."
  }
}
variable "ami_ssm_parameter_name" {
  type        = string
  default     = "/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id"
  description = "Public SSM parameter holding the AMI id, as the _monolithic template had it. Canonical publishes these per release and architecture, so the region never has to be mapped to an AMI id by hand - the template also carried a RegionMapping of hardcoded ids for five regions, which nothing read and which goes stale the moment Canonical republishes"

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
  description = "Instance type for the desktop"

  validation {
    condition     = can(regex("^[a-z0-9]+[a-z0-9-]*\\.[a-z0-9]+$", var.instance_type))
    error_message = "instance_type must be a valid EC2 instance type (e.g. m5.2xlarge)."
  }
}
variable "password" {
  type        = string
  default     = "Ubuntu1234!"
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
