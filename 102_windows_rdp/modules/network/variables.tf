variable "vpc_cidr_block" {
  type        = string
  default     = "10.0.0.0/16"
  description = "CIDR block for the VPC, as the _monolithic template had it"

  validation {
    condition     = can(cidrhost(var.vpc_cidr_block, 0))
    error_message = "vpc_cidr_block must be a valid IPv4 CIDR block (e.g. 10.0.0.0/16)."
  }
}
variable "vpc_name" {
  type        = string
  default     = "windows-rdp-vpc"
  description = "Name tag for the VPC. The _monolithic template tagged it \"vpc\", which is indistinguishable from any other project's VPC in the console - the caller prefixes it instead"

  validation {
    condition     = length(var.vpc_name) > 0
    error_message = "vpc_name must not be empty."
  }
}
variable "internet_gateway_name" {
  type        = string
  default     = "windows-rdp-igw"
  description = "Name tag for the internet gateway"

  validation {
    condition     = length(var.internet_gateway_name) > 0
    error_message = "internet_gateway_name must not be empty."
  }
}
variable "public_subnet_name" {
  type        = string
  default     = "windows-rdp-public"
  description = "Base of the public subnet's Name tag; the zone letter is appended, giving windows-rdp-public-a"

  validation {
    condition     = length(var.public_subnet_name) > 0
    error_message = "public_subnet_name must not be empty."
  }
}
variable "public_route_table_name" {
  type        = string
  default     = "windows-rdp-public-rt"
  description = "Name tag for the public route table"

  validation {
    condition     = length(var.public_route_table_name) > 0
    error_message = "public_route_table_name must not be empty."
  }
}
variable "availability_zone_suffix" {
  type        = string
  default     = "a"
  description = "Zone letter the public subnet is placed in, appended to the region. The _monolithic template's AzMapping keyed its CIDRs on a/b/c and the only subnet it built used a"

  validation {
    condition     = can(regex("^[a-f]$", var.availability_zone_suffix))
    error_message = "availability_zone_suffix must be a single letter a-f."
  }
}
variable "enable_dns_support" {
  type        = bool
  default     = true
  description = "Whether the VPC resolves DNS. True, as the _monolithic template had it, and required: the userdata resolves the Secrets Manager, SSM, PowerShell Gallery, Chocolatey and GitHub endpoints by name"
}
variable "enable_dns_hostnames" {
  type        = bool
  default     = true
  description = "Whether instances get a public DNS name. True, as the _monolithic template had it"
}
variable "public_subnet_tags" {
  type        = map(string)
  default     = {}
  description = "Extra tags merged onto the public subnet, for a caller that needs discovery tags on it. Name is set by this module and wins over anything passed here"

  validation {
    condition     = !contains(keys(var.public_subnet_tags), "Name")
    error_message = "public_subnet_tags must not contain Name, which this module sets from public_subnet_name."
  }
}
