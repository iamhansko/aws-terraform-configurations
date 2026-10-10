# Two zones, a public and a private subnet in each, and a NAT gateway per zone -
# the _monolithic template's shape, reproduced (rules.md C-3: the AZ count is the
# project's call). Two zones because ElastiCache and the VPC-attached Lambda
# functions are spread across them; the GameLift fleet does not live here at all,
# it runs in GameLift's own VPC.
#
# The two NAT gateways are the expensive part of this module and they are the
# template's choice, kept so each private subnet's egress survives the other
# zone. Nothing in this project strictly needs private egress - the two Lambda
# functions attached here only talk to Redis inside the VPC, and Lambda delivers
# their logs and polls their DynamoDB stream from outside it - so a single NAT
# gateway, or none, would also work for the demo. That would be a change from
# the original rather than a conversion, so it is left as the template had it.
locals {
  availability_zone_a = "${var.aws_region}${var.availability_zone_suffixes[0]}"
  availability_zone_c = "${var.aws_region}${var.availability_zone_suffixes[1]}"
}
resource "aws_vpc" "vpc" {
  cidr_block           = var.vpc_cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "${var.name_prefix}-vpc"
  }
}
# vpc_id on the gateway rather than a separate aws_internet_gateway_attachment,
# so every reference to the gateway already implies the attachment. The
# template's split form needed an explicit depends_on on the route to say the
# same thing.
resource "aws_internet_gateway" "internet_gateway" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = "${var.name_prefix}-igw"
  }
}
resource "aws_subnet" "public_subnet_a" {
  vpc_id                  = aws_vpc.vpc.id
  availability_zone       = local.availability_zone_a
  cidr_block              = var.public_subnet_a_cidr_block
  map_public_ip_on_launch = true
  tags = {
    Name = "${var.name_prefix}-public-subnet-a"
  }
}
resource "aws_subnet" "public_subnet_c" {
  vpc_id                  = aws_vpc.vpc.id
  availability_zone       = local.availability_zone_c
  cidr_block              = var.public_subnet_c_cidr_block
  map_public_ip_on_launch = true
  tags = {
    Name = "${var.name_prefix}-public-subnet-c"
  }
}
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = "${var.name_prefix}-public-rt"
  }
}
resource "aws_route" "public_internet_route" {
  route_table_id         = aws_route_table.public_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.internet_gateway.id
}
resource "aws_route_table_association" "public_subnet_a" {
  route_table_id = aws_route_table.public_route_table.id
  subnet_id      = aws_subnet.public_subnet_a.id
}
resource "aws_route_table_association" "public_subnet_c" {
  route_table_id = aws_route_table.public_route_table.id
  subnet_id      = aws_subnet.public_subnet_c.id
}
resource "aws_subnet" "private_subnet_a" {
  vpc_id            = aws_vpc.vpc.id
  availability_zone = local.availability_zone_a
  cidr_block        = var.private_subnet_a_cidr_block
  tags = {
    Name = "${var.name_prefix}-private-subnet-a"
  }
}
resource "aws_subnet" "private_subnet_c" {
  vpc_id            = aws_vpc.vpc.id
  availability_zone = local.availability_zone_c
  cidr_block        = var.private_subnet_c_cidr_block
  tags = {
    Name = "${var.name_prefix}-private-subnet-c"
  }
}
resource "aws_eip" "nat_gateway_a" {
  domain = "vpc"
  tags = {
    Name = "${var.name_prefix}-natgw-a"
  }
}
resource "aws_eip" "nat_gateway_c" {
  domain = "vpc"
  tags = {
    Name = "${var.name_prefix}-natgw-c"
  }
}
# A NAT gateway in a subnet whose VPC has no attached internet gateway is created
# but forwards nothing; AWS documents the gateway as a prerequisite. The subnet
# reference does not order this after the gateway, so it is stated (rules.md D-1).
resource "aws_nat_gateway" "nat_gateway_a" {
  allocation_id = aws_eip.nat_gateway_a.allocation_id
  subnet_id     = aws_subnet.public_subnet_a.id
  tags = {
    Name = "${var.name_prefix}-natgw-a"
  }
  depends_on = [aws_internet_gateway.internet_gateway]
}
resource "aws_nat_gateway" "nat_gateway_c" {
  allocation_id = aws_eip.nat_gateway_c.allocation_id
  subnet_id     = aws_subnet.public_subnet_c.id
  tags = {
    Name = "${var.name_prefix}-natgw-c"
  }
  depends_on = [aws_internet_gateway.internet_gateway]
}
resource "aws_route_table" "private_route_table_a" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = "${var.name_prefix}-private-rt-a"
  }
}
resource "aws_route_table" "private_route_table_c" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = "${var.name_prefix}-private-rt-c"
  }
}
resource "aws_route" "private_nat_route_a" {
  route_table_id         = aws_route_table.private_route_table_a.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat_gateway_a.id
}
resource "aws_route" "private_nat_route_c" {
  route_table_id         = aws_route_table.private_route_table_c.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat_gateway_c.id
}
resource "aws_route_table_association" "private_subnet_a" {
  route_table_id = aws_route_table.private_route_table_a.id
  subnet_id      = aws_subnet.private_subnet_a.id
}
resource "aws_route_table_association" "private_subnet_c" {
  route_table_id = aws_route_table.private_route_table_c.id
  subnet_id      = aws_subnet.private_subnet_c.id
}
