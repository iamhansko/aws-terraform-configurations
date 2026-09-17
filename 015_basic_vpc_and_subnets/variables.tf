variable "aws_region" {
  type        = string
  default     = null
  description = "Target AWS region. When null, falls back to the provider default chain (AWS_REGION, profile, etc.)"
}
variable "prefix" {
  type        = string
  default     = "wsi"
  description = "Prefix for the resources' Name tags (\"wsi\" produces wsi-vpc, wsi-igw, wsi-public-a, wsi-natgw-a, ...). The _monolithic template kept these strings in a CloudFormation-style mappings block; one variable replaces the whole block, because every name in it was the same prefix with a different suffix"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*$", var.prefix))
    error_message = "prefix must be lowercase alphanumeric, optionally with hyphens."
  }
}
variable "vpc_cidr_block" {
  type        = string
  default     = "10.1.0.0/16"
  description = "CIDR block for the VPC. The network module carves four /24 subnets out of it: public a/b then private a/b"

  validation {
    condition     = can(cidrhost(var.vpc_cidr_block, 0))
    error_message = "vpc_cidr_block must be a valid IPv4 CIDR block (e.g. 10.1.0.0/16)."
  }
}
variable "enable_dns_support" {
  type        = bool
  default     = true
  description = "Whether the VPC provides DNS resolution through the Amazon-provided resolver"
}
variable "enable_dns_hostnames" {
  type        = bool
  default     = true
  description = "Whether instances launched in the VPC receive public DNS hostnames"
}
variable "map_public_ip_on_launch" {
  type        = bool
  default     = true
  description = "Whether instances launched into the public subnets get a public IPv4 address automatically. Set false to make the public subnets differ from the private ones by route table alone"
}
