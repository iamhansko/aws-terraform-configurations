# Generated from 000_deprecated/nested/vpc_and_more.yaml by tools/cfn2tf.
# CloudFormation stack -> Terraform root module.
terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }
}
provider "aws" {
  region = var.aws_region
}
variable "aws_region" {
  type        = string
  default     = null
  description = "Target AWS region. Defaults to the provider chain (AWS_REGION)."
}
data "aws_region" "current" {}
# --- Parameters ---
variable "prefix" {
  type        = string
  default     = "project"
  description = "Name Tag Auto-generation (\"project\" -> project-vpc, project-igw, ...)"
}
variable "vpc_cidr_block" {
  type        = string
  default     = "10.0.0.0/16"
  description = "CIDR Block for the VPC to Create (ex 10.0.0.0/16)"
}
variable "number_of_public_subnets" {
  type    = number
  default = 2
}
variable "number_of_private_subnets" {
  type        = number
  default     = 2
  description = "NumberOfPublicSubnets >= NumberOfPrivateSubnets"
}
variable "enable_dns_hostnames_option" {
  type    = string
  default = true
  validation {
    condition     = contains([true, false], var.enable_dns_hostnames_option)
    error_message = "EnableDnsHostnamesOption must be one of: True, False"
  }
}
variable "enable_dns_resolution_option" {
  type    = string
  default = true
  validation {
    condition     = contains([true, false], var.enable_dns_resolution_option)
    error_message = "EnableDnsResolutionOption must be one of: True, False"
  }
}
# --- Mappings / Conditions ---
locals {
  cond_create_public_subnet1  = (!(var.number_of_public_subnets == 0))
  cond_create_public_subnet2  = ((var.number_of_public_subnets == 2) || (var.number_of_public_subnets == 3))
  cond_create_public_subnet3  = (var.number_of_public_subnets == 3)
  cond_create_private_subnet1 = (!(var.number_of_private_subnets == 0))
  cond_create_private_subnet2 = ((var.number_of_private_subnets == 2) || (var.number_of_private_subnets == 3))
  cond_create_private_subnet3 = (var.number_of_private_subnets == 3)
}
# --- Resources ---
resource "aws_vpc" "vpc" {
  cidr_block           = var.vpc_cidr_block
  enable_dns_support   = var.enable_dns_resolution_option
  enable_dns_hostnames = var.enable_dns_hostnames_option
  tags = {
    Name = var.prefix
  }
}
resource "aws_internet_gateway" "internet_gateway" {
  tags = {
    Name = "${var.prefix}-igw"
  }
}
resource "aws_internet_gateway_attachment" "vpc_internet_gateway_attachment" {
  internet_gateway_id = aws_internet_gateway.internet_gateway.id
  vpc_id              = aws_vpc.vpc.id
}
resource "aws_route_table" "public_subnet_route_table" {
  tags = {
    Name = "${var.prefix}-rtb-public"
  }
  vpc_id = aws_vpc.vpc.id
}
resource "aws_route" "public_subnet_route" {
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.internet_gateway.id
  route_table_id         = aws_route_table.public_subnet_route_table.id
}
resource "aws_subnet" "public_subnet1" {
  count                   = local.cond_create_public_subnet1 ? 1 : 0
  availability_zone       = "${data.aws_region.current.region}a"
  cidr_block              = element([for __i in range(6) : cidrsubnet(aws_vpc.vpc.cidr_block, 32 - 8 - tonumber(split("/", aws_vpc.vpc.cidr_block)[1]), __i)], 0)
  map_public_ip_on_launch = true
  tags = {
    Name                     = "${var.prefix}-subnet-public1-${data.aws_region.current.region}a"
    "kubernetes.io/role/elb" = 1
  }
  vpc_id = aws_vpc.vpc.id
}
resource "aws_route_table_association" "public_subnet1_route_table_association" {
  count          = local.cond_create_public_subnet1 ? 1 : 0
  route_table_id = aws_route_table.public_subnet_route_table.id
  subnet_id      = aws_subnet.public_subnet1[0].id
}
resource "aws_subnet" "public_subnet2" {
  count                   = local.cond_create_public_subnet2 ? 1 : 0
  availability_zone       = "${data.aws_region.current.region}b"
  cidr_block              = element([for __i in range(6) : cidrsubnet(aws_vpc.vpc.cidr_block, 32 - 8 - tonumber(split("/", aws_vpc.vpc.cidr_block)[1]), __i)], 1)
  map_public_ip_on_launch = true
  tags = {
    Name                     = "${var.prefix}-subnet-public2-${data.aws_region.current.region}b"
    "kubernetes.io/role/elb" = 1
  }
  vpc_id = aws_vpc.vpc.id
}
resource "aws_route_table_association" "public_subnet2_route_table_association" {
  count          = local.cond_create_public_subnet2 ? 1 : 0
  route_table_id = aws_route_table.public_subnet_route_table.id
  subnet_id      = aws_subnet.public_subnet2[0].id
}
resource "aws_subnet" "public_subnet3" {
  count                   = local.cond_create_public_subnet3 ? 1 : 0
  availability_zone       = "${data.aws_region.current.region}c"
  cidr_block              = element([for __i in range(6) : cidrsubnet(aws_vpc.vpc.cidr_block, 32 - 8 - tonumber(split("/", aws_vpc.vpc.cidr_block)[1]), __i)], 2)
  map_public_ip_on_launch = true
  tags = {
    Name                     = "${var.prefix}-subnet-public3-${data.aws_region.current.region}c"
    "kubernetes.io/role/elb" = 1
  }
  vpc_id = aws_vpc.vpc.id
}
resource "aws_route_table_association" "public_subnet3_route_table_association" {
  count          = local.cond_create_public_subnet3 ? 1 : 0
  route_table_id = aws_route_table.public_subnet_route_table.id
  subnet_id      = aws_subnet.public_subnet3[0].id
}
resource "aws_subnet" "private_subnet1" {
  count             = local.cond_create_private_subnet1 ? 1 : 0
  availability_zone = "${data.aws_region.current.region}a"
  cidr_block        = element([for __i in range(6) : cidrsubnet(aws_vpc.vpc.cidr_block, 32 - 8 - tonumber(split("/", aws_vpc.vpc.cidr_block)[1]), __i)], 3)
  tags = {
    Name                              = "${var.prefix}-subnet-private1-${data.aws_region.current.region}a"
    "kubernetes.io/role/internal-elb" = 1
  }
  vpc_id = aws_vpc.vpc.id
}
resource "aws_eip" "nat_gateway1_elastic_ip" {
  count = local.cond_create_private_subnet1 ? 1 : 0
}
resource "aws_nat_gateway" "nat_gateway1" {
  count         = local.cond_create_private_subnet1 ? 1 : 0
  allocation_id = aws_eip.nat_gateway1_elastic_ip[0].allocation_id
  subnet_id     = aws_subnet.public_subnet1[0].id
  tags = {
    Name = "${var.prefix}-nat-public1-${data.aws_region.current.region}a"
  }
}
resource "aws_route_table" "private_subnet1_route_table" {
  count = local.cond_create_private_subnet1 ? 1 : 0
  tags = {
    Name = "${var.prefix}-rtb-private1-${data.aws_region.current.region}a"
  }
  vpc_id = aws_vpc.vpc.id
}
resource "aws_route_table_association" "private_subnet1_route_table_association" {
  count          = local.cond_create_private_subnet1 ? 1 : 0
  route_table_id = aws_route_table.private_subnet1_route_table[0].id
  subnet_id      = aws_subnet.private_subnet1[0].id
}
resource "aws_route" "private_subnet1_route" {
  count                  = local.cond_create_private_subnet1 ? 1 : 0
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat_gateway1[0].id
  route_table_id         = aws_route_table.private_subnet1_route_table[0].id
}
resource "aws_subnet" "private_subnet2" {
  count             = local.cond_create_private_subnet2 ? 1 : 0
  availability_zone = "${data.aws_region.current.region}b"
  cidr_block        = element([for __i in range(6) : cidrsubnet(aws_vpc.vpc.cidr_block, 32 - 8 - tonumber(split("/", aws_vpc.vpc.cidr_block)[1]), __i)], 4)
  tags = {
    Name                              = "${var.prefix}-subnet-private2-${data.aws_region.current.region}b"
    "kubernetes.io/role/internal-elb" = 1
  }
  vpc_id = aws_vpc.vpc.id
}
resource "aws_eip" "nat_gateway2_elastic_ip" {
  count = local.cond_create_private_subnet2 ? 1 : 0
}
resource "aws_nat_gateway" "nat_gateway2" {
  count         = local.cond_create_private_subnet2 ? 1 : 0
  allocation_id = aws_eip.nat_gateway2_elastic_ip[0].allocation_id
  subnet_id     = aws_subnet.public_subnet2[0].id
  tags = {
    Name = "${var.prefix}-nat-public2-${data.aws_region.current.region}b"
  }
}
resource "aws_route_table" "private_subnet2_route_table" {
  count = local.cond_create_private_subnet2 ? 1 : 0
  tags = {
    Name = "${var.prefix}-rtb-private2-${data.aws_region.current.region}b"
  }
  vpc_id = aws_vpc.vpc.id
}
resource "aws_route_table_association" "private_subnet2_route_table_association" {
  count          = local.cond_create_private_subnet2 ? 1 : 0
  route_table_id = aws_route_table.private_subnet2_route_table[0].id
  subnet_id      = aws_subnet.private_subnet2[0].id
}
resource "aws_route" "private_subnet2_route" {
  count                  = local.cond_create_private_subnet2 ? 1 : 0
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat_gateway2[0].id
  route_table_id         = aws_route_table.private_subnet2_route_table[0].id
}
resource "aws_subnet" "private_subnet3" {
  count             = local.cond_create_private_subnet3 ? 1 : 0
  availability_zone = "${data.aws_region.current.region}c"
  cidr_block        = element([for __i in range(6) : cidrsubnet(aws_vpc.vpc.cidr_block, 32 - 8 - tonumber(split("/", aws_vpc.vpc.cidr_block)[1]), __i)], 5)
  tags = {
    Name                              = "${var.prefix}-subnet-private3-${data.aws_region.current.region}c"
    "kubernetes.io/role/internal-elb" = 1
  }
  vpc_id = aws_vpc.vpc.id
}
resource "aws_eip" "nat_gateway3_elastic_ip" {
  count = local.cond_create_private_subnet3 ? 1 : 0
}
resource "aws_nat_gateway" "nat_gateway3" {
  count         = local.cond_create_private_subnet3 ? 1 : 0
  allocation_id = aws_eip.nat_gateway3_elastic_ip[0].allocation_id
  subnet_id     = aws_subnet.public_subnet3[0].id
  tags = {
    Name = "${var.prefix}-nat-public3-${data.aws_region.current.region}c"
  }
}
resource "aws_route_table" "private_subnet3_route_table" {
  count = local.cond_create_private_subnet3 ? 1 : 0
  tags = {
    Name = "${var.prefix}-rtb-private3-${data.aws_region.current.region}c"
  }
  vpc_id = aws_vpc.vpc.id
}
resource "aws_route_table_association" "private_subnet3_route_table_association" {
  count          = local.cond_create_private_subnet3 ? 1 : 0
  route_table_id = aws_route_table.private_subnet3_route_table[0].id
  subnet_id      = aws_subnet.private_subnet3[0].id
}
resource "aws_route" "private_subnet3_route" {
  count                  = local.cond_create_private_subnet3 ? 1 : 0
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat_gateway3[0].id
  route_table_id         = aws_route_table.private_subnet3_route_table[0].id
}
# --- Outputs ---
# CloudFormation output: VpcId
output "vpc_id" {
  value = aws_vpc.vpc.id
}
# CloudFormation output: PublicSubnet1Id
output "public_subnet1_id" {
  value = (local.cond_create_public_subnet1 ? aws_subnet.public_subnet1[0].id : null)
}
# CloudFormation output: PublicSubnet2Id
output "public_subnet2_id" {
  value = (local.cond_create_public_subnet2 ? aws_subnet.public_subnet2[0].id : null)
}
# CloudFormation output: PublicSubnet3Id
output "public_subnet3_id" {
  value = (local.cond_create_public_subnet3 ? aws_subnet.public_subnet3[0].id : null)
}
# CloudFormation output: PrivateSubnet1Id
output "private_subnet1_id" {
  value = (local.cond_create_private_subnet1 ? aws_subnet.private_subnet1[0].id : null)
}
# CloudFormation output: PrivateSubnet2Id
output "private_subnet2_id" {
  value = (local.cond_create_private_subnet2 ? aws_subnet.private_subnet2[0].id : null)
}
# CloudFormation output: PrivateSubnet3Id
output "private_subnet3_id" {
  value = (local.cond_create_private_subnet3 ? aws_subnet.private_subnet3[0].id : null)
}
