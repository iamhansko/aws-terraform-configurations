data "aws_region" "current" {}
locals {
  # Carves the VPC CIDR into /24s regardless of the VPC prefix length, so a 10.0.0.0/16 VPC
  # yields 10.0.0.0/24, 10.0.1.0/24, ... The indices below interleave public and private per
  # zone (public a/b/c = 0/2/4, private a/b/c = 1/3/5), which is the mapping the _monolithic
  # template used, so the subnet CIDRs stay identical.
  subnet_newbits = 24 - tonumber(split("/", var.vpc_cidr_block)[1])
}
# Three availability zones, as the _monolithic template had them, and the count matters here
# rather than being incidental (rules.md C-3). The demo's nginx Deployment spreads on
# topology.kubernetes.io/zone, so the number of zones is the number of buckets that
# constraint has to balance across - with two, a twelve-replica Deployment spreading by zone
# and one spreading by hostname look almost the same. Each zone does cost a NAT gateway.
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
  cidr_block              = cidrsubnet(var.vpc_cidr_block, local.subnet_newbits, 2)
  map_public_ip_on_launch = true
  tags = merge(var.public_subnet_tags, {
    Name = join("-", [var.public_subnet_name, "b"])
  })
}
resource "aws_subnet" "public_subnet_c" {
  vpc_id                  = aws_vpc.vpc.id
  availability_zone       = "${data.aws_region.current.region}c"
  cidr_block              = cidrsubnet(var.vpc_cidr_block, local.subnet_newbits, 4)
  map_public_ip_on_launch = true
  tags = merge(var.public_subnet_tags, {
    Name = join("-", [var.public_subnet_name, "c"])
  })
}
resource "aws_subnet" "private_subnet_a" {
  vpc_id            = aws_vpc.vpc.id
  availability_zone = "${data.aws_region.current.region}a"
  cidr_block        = cidrsubnet(var.vpc_cidr_block, local.subnet_newbits, 1)
  tags = merge(var.private_subnet_tags, {
    Name = join("-", [var.private_subnet_name, "a"])
  })
}
resource "aws_subnet" "private_subnet_b" {
  vpc_id            = aws_vpc.vpc.id
  availability_zone = "${data.aws_region.current.region}b"
  cidr_block        = cidrsubnet(var.vpc_cidr_block, local.subnet_newbits, 3)
  tags = merge(var.private_subnet_tags, {
    Name = join("-", [var.private_subnet_name, "b"])
  })
}
resource "aws_subnet" "private_subnet_c" {
  vpc_id            = aws_vpc.vpc.id
  availability_zone = "${data.aws_region.current.region}c"
  cidr_block        = cidrsubnet(var.vpc_cidr_block, local.subnet_newbits, 5)
  tags = merge(var.private_subnet_tags, {
    Name = join("-", [var.private_subnet_name, "c"])
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
resource "aws_route_table_association" "public_subnet_c_route_table_association" {
  route_table_id = aws_route_table.public_subnet_route_table.id
  subnet_id      = aws_subnet.public_subnet_c.id
}
# A NAT gateway per zone, and a private route table per zone pointing at it, so a zone
# failure cannot take out egress for another zone's private subnet. It also matters for what
# this project shows: the autoscaler launches nodes into whichever zone has the Pending pods,
# and a node in a zone with no egress never finishes joining.
resource "aws_eip" "nat_gateway_a_elastic_ip" {}
resource "aws_nat_gateway" "nat_gateway_a" {
  allocation_id = aws_eip.nat_gateway_a_elastic_ip.allocation_id
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
resource "aws_route" "private_subnet_a_route" {
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat_gateway_a.id
  route_table_id         = aws_route_table.private_subnet_a_route_table.id
}
resource "aws_eip" "nat_gateway_b_elastic_ip" {}
resource "aws_nat_gateway" "nat_gateway_b" {
  allocation_id = aws_eip.nat_gateway_b_elastic_ip.allocation_id
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
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat_gateway_b.id
  route_table_id         = aws_route_table.private_subnet_b_route_table.id
}
resource "aws_eip" "nat_gateway_c_elastic_ip" {}
resource "aws_nat_gateway" "nat_gateway_c" {
  allocation_id = aws_eip.nat_gateway_c_elastic_ip.allocation_id
  subnet_id     = aws_subnet.public_subnet_c.id
  tags = {
    Name = join("-", [var.nat_gateway_name, "c"])
  }
}
resource "aws_route_table" "private_subnet_c_route_table" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = join("-", [var.private_route_table_name, "c"])
  }
}
resource "aws_route_table_association" "private_subnet_c_route_table_association" {
  route_table_id = aws_route_table.private_subnet_c_route_table.id
  subnet_id      = aws_subnet.private_subnet_c.id
}
resource "aws_route" "private_subnet_c_route" {
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat_gateway_c.id
  route_table_id         = aws_route_table.private_subnet_c_route_table.id
}
