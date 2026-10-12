variable "name" {
  type        = string
  description = "Base name for the Name tags, the flow log group and the flow log role"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,40}$", var.name))
    error_message = "name must be 2-41 characters of lowercase letters, digits and hyphens."
  }
}
variable "region" {
  type        = string
  description = "Region the VPC is in. Passed in rather than read from a data source, because it builds the zone names and the S3 endpoint's service name"

  validation {
    condition     = can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]$", var.region))
    error_message = "region must be an AWS region name such as ap-northeast-2."
  }
}
variable "vpc_cidr_block" {
  type        = string
  default     = "10.0.0.0/16"
  description = "CIDR block of the VPC, 10.0.0.0/16 as CDK's ec2.Vpc defaults it"

  validation {
    condition     = can(cidrhost(var.vpc_cidr_block, 0))
    error_message = "vpc_cidr_block must be a valid IPv4 CIDR block (e.g. 10.0.0.0/16)."
  }
  validation {
    # Every subnet is a /24 carved with cidrsubnet(..., 24 - prefix, n); a prefix longer than /24 makes newbits
    # negative and fails with a message that does not name this variable.
    condition     = tonumber(split("/", var.vpc_cidr_block)[1]) <= 22
    error_message = "vpc_cidr_block must be /22 or shorter, because it is cut into four /24 subnets."
  }
}
variable "availability_zone_suffixes" {
  type        = list(string)
  default     = ["a", "b"]
  description = "The two zone letters the subnets and the NAT instances go in. The blueprint's max_azs=2 took the region's first two zones, which is a and b"

  validation {
    condition     = length(var.availability_zone_suffixes) == 2 && alltrue([for suffix in var.availability_zone_suffixes : can(regex("^[a-z]$", suffix))])
    error_message = "availability_zone_suffixes must contain exactly two single lowercase letters."
  }
  validation {
    condition     = length(distinct(var.availability_zone_suffixes)) == 2
    error_message = "availability_zone_suffixes entries must differ - an ALB needs subnets in two different zones."
  }
}
variable "nat_instance_type" {
  type        = string
  default     = "t4g.nano"
  description = "Instance type of the NAT instances, t4g.nano as the blueprint had it. It has to be an arm64 (Graviton) type, because the AMI parameter below is the arm64 one"

  validation {
    condition     = can(regex("^[a-z][a-z0-9]*g[a-z]*\\.[a-z0-9]+$", var.nat_instance_type))
    error_message = "nat_instance_type must be a Graviton instance type such as t4g.nano, to match the arm64 AMI."
  }
}
variable "nat_instance_ami_parameter" {
  type        = string
  default     = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-arm64"
  description = "Public SSM parameter the NAT instance AMI is read from - the one CDK's NatInstanceProviderV2 resolves for an arm64 instance type"

  validation {
    condition     = startswith(var.nat_instance_ami_parameter, "/aws/service/")
    error_message = "nat_instance_ami_parameter must be an AWS public parameter path under /aws/service/."
  }
}
variable "nat_security_group_name" {
  type        = string
  description = "Name of the NAT instances' security group"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.nat_security_group_name)) && !startswith(var.nat_security_group_name, "sg-")
    error_message = "nat_security_group_name must be 1-255 characters from the set EC2 accepts for a security group name (no apostrophe) and must not start with \"sg-\"."
  }
}
variable "nat_security_group_description" {
  type        = string
  default     = "Security Group for NAT instances"
  description = "Description of the NAT instances' security group, as CDK wrote it. Changing it replaces the group (rules.md F-1)"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.nat_security_group_description))
    error_message = "nat_security_group_description must be 1-255 characters from the set EC2 accepts for a security group description. An apostrophe is not allowed - EC2 rejects it only at apply."
  }
}
variable "flow_log_retention_days" {
  type        = number
  default     = 731
  description = "Retention of the VPC flow log, two years as CDK's FlowLog created its log group"

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.flow_log_retention_days)
    error_message = "flow_log_retention_days must be one of the retention periods CloudWatch Logs accepts."
  }
}
