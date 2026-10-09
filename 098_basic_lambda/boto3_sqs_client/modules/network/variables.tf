variable "vpc_cidr_block" {
  type        = string
  default     = "10.102.0.0/16"
  description = "CIDR of the VPC, as the _monolithic template had it. The subnet below is carved out of it rather than stated separately, so this is the only address decision in the module"

  validation {
    condition     = can(cidrhost(var.vpc_cidr_block, 0))
    error_message = "vpc_cidr_block must be a valid IPv4 CIDR block (e.g. 10.102.0.0/16)."
  }
  validation {
    # /24 is what the subnet calculation below produces, so a VPC prefix longer than that would ask
    # cidrsubnet for a negative number of new bits and fail the plan with an unhelpful arithmetic error.
    condition     = tonumber(split("/", var.vpc_cidr_block)[1]) <= 24
    error_message = "vpc_cidr_block must be /24 or shorter, because the public subnet is carved out of it as a /24."
  }
}
variable "vpc_name" {
  type        = string
  default     = "queue-vpc"
  description = "Name tag of the VPC"

  validation {
    condition     = length(var.vpc_name) > 0
    error_message = "vpc_name must not be empty."
  }
}
variable "enable_dns_support" {
  type        = bool
  default     = true
  description = "Whether the VPC resolves DNS. True, as the _monolithic template set it, and not optional in practice: both instances install packages from the internet and reach SQS and CloudWatch by hostname"
}
variable "enable_dns_hostnames" {
  type        = bool
  default     = true
  description = "Whether instances get public DNS names. True, as the _monolithic template set it"
}
variable "internet_gateway_name" {
  type        = string
  default     = "queue-igw"
  description = "Name tag of the internet gateway"

  validation {
    condition     = length(var.internet_gateway_name) > 0
    error_message = "internet_gateway_name must not be empty."
  }
}
variable "public_subnet_name" {
  type        = string
  default     = "queue-pub"
  description = "Name tag of the public subnet, with the availability zone letter appended. The _monolithic template tagged it queue-pub-a, which this reproduces"

  validation {
    condition     = length(var.public_subnet_name) > 0
    error_message = "public_subnet_name must not be empty."
  }
}
variable "public_route_table_name" {
  type        = string
  default     = "queue-pub-rt"
  description = "Name tag of the public route table"

  validation {
    condition     = length(var.public_route_table_name) > 0
    error_message = "public_route_table_name must not be empty."
  }
}
variable "availability_zone_suffix" {
  type        = string
  default     = "a"
  description = "Letter of the availability zone the subnet is created in, appended to the region name. The _monolithic template hardcoded the region's a zone"

  validation {
    condition     = can(regex("^[a-z]$", var.availability_zone_suffix))
    error_message = "availability_zone_suffix must be a single lowercase letter (e.g. a)."
  }
}
variable "public_subnet_tags" {
  type        = map(string)
  default     = {}
  description = "Extra tags merged onto the public subnet. Empty here - there is no load balancer controller in this project looking for kubernetes.io/role/elb - but kept so a caller can tag the subnet without the module changing"

  validation {
    # AWS's own limits. A key over 128 characters or a value over 256 is rejected by the CreateTags call,
    # which happens during the subnet's create and so fails the apply rather than the plan.
    condition = alltrue([for key, value in var.public_subnet_tags :
      length(key) > 0 && length(key) <= 128 && length(value) <= 256
    ])
    error_message = "public_subnet_tags keys must be 1-128 characters and values at most 256 - the limits EC2's CreateTags enforces."
  }
  validation {
    condition     = !anytrue([for key in keys(var.public_subnet_tags) : key == "Name"])
    error_message = "public_subnet_tags must not contain Name - the module sets that tag itself from public_subnet_name and the availability zone, and a Name here would be silently overwritten by the merge."
  }
}
