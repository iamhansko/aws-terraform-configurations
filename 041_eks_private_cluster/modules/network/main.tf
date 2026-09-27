data "aws_region" "current" {}
locals {
  # Carves the VPC CIDR into /24s regardless of the VPC prefix length, so a
  # 10.0.0.0/16 VPC yields 10.0.0.0/24, 10.0.1.0/24, ... The index mapping below
  # (public a/b = 0/1, private a/b = 3/4) matches the original _monolithic
  # template so subnet CIDRs stay identical. Index 2 is deliberately skipped: the
  # CloudFormation AZ mapping carried a third zone that the stack never created,
  # and its public subnet held that slot.
  subnet_newbits = 24 - tonumber(split("/", var.vpc_cidr_block)[1])
}
# Two availability zones rather than the three the EKS projects in this
# repository use. Three is a requirement of EKS control plane placement, not of
# a VPC, and each zone here costs a NAT gateway - so this project spans the two
# the _monolithic template had.
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
resource "aws_internet_gateway_attachment" "vpc_internet_gateway_attachment" {
  internet_gateway_id = aws_internet_gateway.internet_gateway.id
  vpc_id              = aws_vpc.vpc.id
}
resource "aws_route_table" "public_subnet_route_table" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = var.public_route_table_name
  }
}
resource "aws_route" "public_subnet_route" {
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.internet_gateway.id
  route_table_id         = aws_route_table.public_subnet_route_table.id
}
resource "aws_subnet" "public_subnet_a" {
  vpc_id                  = aws_vpc.vpc.id
  availability_zone       = "${data.aws_region.current.region}a"
  cidr_block              = cidrsubnet(var.vpc_cidr_block, local.subnet_newbits, 0)
  map_public_ip_on_launch = true
  tags = merge(var.public_subnet_tags, {
    Name = join("-", [var.public_subnet_name, "a"])
  })
}
resource "aws_subnet" "public_subnet_b" {
  vpc_id                  = aws_vpc.vpc.id
  availability_zone       = "${data.aws_region.current.region}b"
  cidr_block              = cidrsubnet(var.vpc_cidr_block, local.subnet_newbits, 1)
  map_public_ip_on_launch = true
  tags = merge(var.public_subnet_tags, {
    Name = join("-", [var.public_subnet_name, "b"])
  })
}
resource "aws_subnet" "private_subnet_a" {
  vpc_id            = aws_vpc.vpc.id
  availability_zone = "${data.aws_region.current.region}a"
  cidr_block        = cidrsubnet(var.vpc_cidr_block, local.subnet_newbits, 3)
  tags = merge(var.private_subnet_tags, {
    Name = join("-", [var.private_subnet_name, "a"])
  })
}
resource "aws_subnet" "private_subnet_b" {
  vpc_id            = aws_vpc.vpc.id
  availability_zone = "${data.aws_region.current.region}b"
  cidr_block        = cidrsubnet(var.vpc_cidr_block, local.subnet_newbits, 4)
  tags = merge(var.private_subnet_tags, {
    Name = join("-", [var.private_subnet_name, "b"])
  })
}
resource "aws_route_table_association" "public_subnet_a_route_table_association" {
  route_table_id = aws_route_table.public_subnet_route_table.id
  subnet_id      = aws_subnet.public_subnet_a.id
}
resource "aws_route_table_association" "public_subnet_b_route_table_association" {
  route_table_id = aws_route_table.public_subnet_route_table.id
  subnet_id      = aws_subnet.public_subnet_b.id
}
# Off in this project. A private cluster reaches AWS APIs through the VPC
# endpoints the caller creates instead, so the private subnets deliberately have
# no route to the internet at all - that absence is the thing being demonstrated,
# and it is why every image the cluster runs has to come through an ECR
# pull-through cache rather than from a public registry (rules.md B-4).
resource "aws_eip" "nat_gateway_a_elastic_ip" {
  count = var.enable_nat_gateway ? 1 : 0
}
resource "aws_nat_gateway" "nat_gateway_a" {
  count         = var.enable_nat_gateway ? 1 : 0
  allocation_id = aws_eip.nat_gateway_a_elastic_ip[0].allocation_id
  subnet_id     = aws_subnet.public_subnet_a.id
  tags = {
    Name = join("-", [var.nat_gateway_name, "a"])
  }
}
resource "aws_route_table" "private_subnet_a_route_table" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = join("-", [var.private_route_table_name, "a"])
  }
}
resource "aws_route_table_association" "private_subnet_a_route_table_association" {
  route_table_id = aws_route_table.private_subnet_a_route_table.id
  subnet_id      = aws_subnet.private_subnet_a.id
}
# No default route when the NAT gateway is off: the route table still exists and
# is still associated, so the S3 gateway endpoint has somewhere to add its prefix
# list route, but nothing leaves the VPC by this path.
resource "aws_route" "private_subnet_a_route" {
  count                  = var.enable_nat_gateway ? 1 : 0
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat_gateway_a[0].id
  route_table_id         = aws_route_table.private_subnet_a_route_table.id
}
# A NAT gateway per zone, and a private route table per zone pointing at it, so
# a zone failure cannot take out egress for the other zone's private subnet.
resource "aws_eip" "nat_gateway_b_elastic_ip" {
  count = var.enable_nat_gateway ? 1 : 0
}
resource "aws_nat_gateway" "nat_gateway_b" {
  count         = var.enable_nat_gateway ? 1 : 0
  allocation_id = aws_eip.nat_gateway_b_elastic_ip[0].allocation_id
  subnet_id     = aws_subnet.public_subnet_b.id
  tags = {
    Name = join("-", [var.nat_gateway_name, "b"])
  }
}
resource "aws_route_table" "private_subnet_b_route_table" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = join("-", [var.private_route_table_name, "b"])
  }
}
resource "aws_route_table_association" "private_subnet_b_route_table_association" {
  route_table_id = aws_route_table.private_subnet_b_route_table.id
  subnet_id      = aws_subnet.private_subnet_b.id
}
resource "aws_route" "private_subnet_b_route" {
  count                  = var.enable_nat_gateway ? 1 : 0
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat_gateway_b[0].id
  route_table_id         = aws_route_table.private_subnet_b_route_table.id
}
