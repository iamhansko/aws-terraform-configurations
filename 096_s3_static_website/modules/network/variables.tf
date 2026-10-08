variable "vpc_cidr_block" {
  type        = string
  description = "CIDR of the VPC, as the _monolithic template had it. The subnet is carved out of this with cidrsubnet rather than written separately, so the two cannot disagree"

  validation {
    condition     = can(cidrhost(var.vpc_cidr_block, 0))
    error_message = "vpc_cidr_block must be a valid IPv4 CIDR block, e.g. 10.0.0.0/16."
  }
  validation {
    # The subnet is cidrsubnet(cidr, 24 - prefix, 0), and a negative newbits is a plan error that reads
    # "Invalid value for \"newbits\" parameter" rather than anything about the VPC being too small.
    condition     = tonumber(split("/", var.vpc_cidr_block)[1]) <= 24
    error_message = "vpc_cidr_block must be /24 or larger (a smaller prefix number), because the public subnet is carved out of it as a /24."
  }
}
variable "vpc_name" {
  type        = string
  description = "Name tag of the VPC"

  validation {
    condition     = length(var.vpc_name) > 0
    error_message = "vpc_name must not be empty."
  }
}
variable "internet_gateway_name" {
  type        = string
  description = "Name tag of the internet gateway"

  validation {
    condition     = length(var.internet_gateway_name) > 0
    error_message = "internet_gateway_name must not be empty."
  }
}
variable "public_route_table_name" {
  type        = string
  description = "Name tag of the public route table"

  validation {
    condition     = length(var.public_route_table_name) > 0
    error_message = "public_route_table_name must not be empty."
  }
}
variable "public_subnet_name" {
  type        = string
  description = "Base of the public subnet's name tag. The zone suffix is appended, so the tag says which zone the subnet is in - the _monolithic template tagged it flatly public-subnet and there was no way to tell from the console"

  validation {
    condition     = length(var.public_subnet_name) > 0
    error_message = "public_subnet_name must not be empty."
  }
}
variable "availability_zone_suffix" {
  type        = string
  default     = "a"
  description = "Letter appended to the region name to pick the zone, reproducing the region-plus-a the _monolithic template interpolated inline. A letter rather than a full zone name so the module works in any region"

  validation {
    condition     = can(regex("^[a-f]$", var.availability_zone_suffix))
    error_message = "availability_zone_suffix must be a single letter a-f."
  }
}
variable "public_route_destination_cidr_block" {
  type        = string
  default     = "0.0.0.0/0"
  description = "Destination of the route to the internet gateway. The default route, as the _monolithic template had it - the seeder instance reaches github.com and the S3 API through it"

  validation {
    condition     = can(cidrhost(var.public_route_destination_cidr_block, 0))
    error_message = "public_route_destination_cidr_block must be a valid IPv4 CIDR block, e.g. 0.0.0.0/0."
  }
}
variable "enable_dns_support" {
  type        = bool
  default     = true
  description = "Whether the Amazon DNS server answers in this VPC. True, as the _monolithic template had it, and required: the seeder resolves github.com and the regional S3 endpoint"
}
variable "enable_dns_hostnames" {
  type        = bool
  default     = true
  description = "Whether instances get public DNS names. True, as the _monolithic template had it"
}
variable "map_public_ip_on_launch" {
  type        = bool
  default     = true
  description = "Whether instances launched in the public subnet get a public address by default. True, as the _monolithic template had it. False leaves the seeder unable to reach the internet, which surfaces as an empty bucket rather than as a failed apply"
}
