variable "name" {
  type        = string
  description = "Name tag of the VPC and the internet gateway, and the prefix of every other Name tag in the module - subnets get -public-<zone> and -private-<zone>, route tables -public and -private, the NAT gateway -<zone>"
  validation {
    # Tag values may be up to 256 characters; the longest suffix is "-private-" plus a zone name.
    condition     = length(var.name) > 0 && length(var.name) <= 220
    error_message = "name must be 1-220 characters, so the longest Name tag built from it stays within the 256 characters EC2 allows for a tag value."
  }
}
variable "vpc_cidr_block" {
  type        = string
  description = "CIDR block of the VPC. Every subnet is carved out of it: private subnets four bits longer, public subnets eight bits longer starting at index 48"
  validation {
    condition     = can(cidrhost(var.vpc_cidr_block, 0))
    error_message = "vpc_cidr_block must be a valid IPv4 CIDR block (e.g. 10.0.0.0/16)."
  }
  validation {
    # /16 is the largest VPC AWS accepts. At /20 the public subnets are already /28 - eleven usable
    # addresses each, after AWS reserves five - so anything longer cannot hold a NAT gateway and a
    # workbench at all.
    #
    # Wrapped in try() because Terraform evaluates every validation block, so a value with no "/" would
    # otherwise fail here with an index error instead of the message above.
    condition     = try(tonumber(split("/", var.vpc_cidr_block)[1]) >= 16 && tonumber(split("/", var.vpc_cidr_block)[1]) <= 20, true)
    error_message = "vpc_cidr_block must be between /16 and /20: AWS rejects a VPC larger than /16, and a VPC smaller than /20 leaves the public subnets carved from it too small to use."
  }
}
variable "public_subnet_tags" {
  type        = map(string)
  default     = {}
  description = "Tags merged into every public subnet, under the Name tag this module sets"
}
variable "private_subnet_tags" {
  type        = map(string)
  default     = {}
  description = "Tags merged into every private subnet, under the Name tag this module sets"
}
