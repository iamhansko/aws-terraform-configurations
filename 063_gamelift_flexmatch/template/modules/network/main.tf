locals {
  # Two zones, named rather than generated, which is what the _monolithic template declared. Two because the
  # ElastiCache subnet group and the VPC-attached Lambda functions span both; this project has no EKS control
  # plane asking for three (rules.md C-3).
  zone_a = "${var.region}${var.availability_zone_suffixes[0]}"
  zone_b = "${var.region}${var.availability_zone_suffixes[1]}"
}
resource "aws_vpc" "vpc" {
  cidr_block           = var.vpc_cidr_block
  enable_dns_support   = var.enable_dns_support
  enable_dns_hostnames = var.enable_dns_hostnames
  tags = {
    Name = var.vpc_name
  }
}
resource "aws_internet_gateway" "internet_gateway" {
  tags = {
    Name = var.internet_gateway_name
  }
}
# A separate attachment rather than vpc_id on the gateway, which is how the conversion rendered
# AWS::EC2::VPCGatewayAttachment. The two spellings conflict, so the gateway above carries no vpc_id.
resource "aws_internet_gateway_attachment" "vpc_internet_gateway_attachment" {
  internet_gateway_id = aws_internet_gateway.internet_gateway.id
  vpc_id              = aws_vpc.vpc.id
}
# --- Public subnets: the code-server workbench ------------------------------------------------------------
resource "aws_subnet" "public_subnet_a" {
  vpc_id                  = aws_vpc.vpc.id
  availability_zone       = local.zone_a
  cidr_block              = var.public_subnet_cidr_blocks[0]
  map_public_ip_on_launch = true
  tags = {
    Name = join("-", [var.public_subnet_name, var.availability_zone_suffixes[0]])
  }
}
resource "aws_subnet" "public_subnet_b" {
  vpc_id                  = aws_vpc.vpc.id
  availability_zone       = local.zone_b
  cidr_block              = var.public_subnet_cidr_blocks[1]
  map_public_ip_on_launch = true
  tags = {
    Name = join("-", [var.public_subnet_name, var.availability_zone_suffixes[1]])
  }
}
resource "aws_route_table" "public_subnet_route_table" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = var.public_route_table_name
  }
}
resource "aws_route" "public_subnet_route" {
  route_table_id         = aws_route_table.public_subnet_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.internet_gateway.id
  # gateway_id names the gateway, not the attachment, and a route to a gateway that is not attached yet is
  # rejected (rules.md D-1).
  depends_on = [aws_internet_gateway_attachment.vpc_internet_gateway_attachment]
}
resource "aws_route_table_association" "public_subnet_a_route_table_association" {
  route_table_id = aws_route_table.public_subnet_route_table.id
  subnet_id      = aws_subnet.public_subnet_a.id
}
resource "aws_route_table_association" "public_subnet_b_route_table_association" {
  route_table_id = aws_route_table.public_subnet_route_table.id
  subnet_id      = aws_subnet.public_subnet_b.id
}
# --- Private subnets: ElastiCache and the two VPC-attached Lambda functions ----------------------------------
#
# One NAT gateway and one route table per zone, reproduced from the _monolithic template, and this is the most
# expensive part of the network: each gateway is billed by the hour whether or not it carries traffic, plus its
# elastic IP. As this project is built, nothing sends traffic through them. The two VPC-attached functions
# (game-rank-update and game-rank-reader) only talk to Redis inside the VPC, and ElastiCache needs no egress.
# They are kept because the original declared them and because the first AWS SDK call either function makes
# would otherwise time out from a subnet with no route out - but they are pure cost until then.
resource "aws_subnet" "private_subnet_a" {
  vpc_id            = aws_vpc.vpc.id
  availability_zone = local.zone_a
  cidr_block        = var.private_subnet_cidr_blocks[0]
  tags = {
    Name = join("-", [var.private_subnet_name, var.availability_zone_suffixes[0]])
  }
}
resource "aws_subnet" "private_subnet_b" {
  vpc_id            = aws_vpc.vpc.id
  availability_zone = local.zone_b
  cidr_block        = var.private_subnet_cidr_blocks[1]
  tags = {
    Name = join("-", [var.private_subnet_name, var.availability_zone_suffixes[1]])
  }
}
resource "aws_eip" "nat_gateway_elastic_ip_a" {
  tags = {
    Name = join("-", [var.nat_gateway_name, var.availability_zone_suffixes[0]])
  }
}
resource "aws_eip" "nat_gateway_elastic_ip_b" {
  tags = {
    Name = join("-", [var.nat_gateway_name, var.availability_zone_suffixes[1]])
  }
}
resource "aws_nat_gateway" "nat_gateway_a" {
  allocation_id = aws_eip.nat_gateway_elastic_ip_a.allocation_id
  subnet_id     = aws_subnet.public_subnet_a.id
  tags = {
    Name = join("-", [var.nat_gateway_name, var.availability_zone_suffixes[0]])
  }
  # A NAT gateway with no path to an attached internet gateway is created and carries nothing (rules.md D-1).
  depends_on = [aws_internet_gateway_attachment.vpc_internet_gateway_attachment]
}
resource "aws_nat_gateway" "nat_gateway_b" {
  allocation_id = aws_eip.nat_gateway_elastic_ip_b.allocation_id
  subnet_id     = aws_subnet.public_subnet_b.id
  tags = {
    Name = join("-", [var.nat_gateway_name, var.availability_zone_suffixes[1]])
  }
  depends_on = [aws_internet_gateway_attachment.vpc_internet_gateway_attachment]
}
resource "aws_route_table" "private_subnet_a_route_table" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = join("-", [var.private_route_table_name, var.availability_zone_suffixes[0]])
  }
}
resource "aws_route" "private_subnet_a_route" {
  route_table_id         = aws_route_table.private_subnet_a_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat_gateway_a.id
}
resource "aws_route_table_association" "private_subnet_a_route_table_association" {
  route_table_id = aws_route_table.private_subnet_a_route_table.id
  subnet_id      = aws_subnet.private_subnet_a.id
}
resource "aws_route_table" "private_subnet_b_route_table" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = join("-", [var.private_route_table_name, var.availability_zone_suffixes[1]])
  }
}
resource "aws_route" "private_subnet_b_route" {
  route_table_id         = aws_route_table.private_subnet_b_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat_gateway_b.id
}
resource "aws_route_table_association" "private_subnet_b_route_table_association" {
  route_table_id = aws_route_table.private_subnet_b_route_table.id
  subnet_id      = aws_subnet.private_subnet_b.id
}
