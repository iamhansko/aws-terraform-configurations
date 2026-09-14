data "aws_region" "current" {}
locals {
  # Carves the VPC CIDR into /24s regardless of the VPC prefix length, so a
  # 10.0.0.0/16 VPC yields 10.0.0.0/24, 10.0.1.0/24, ... The index mapping
  # below (private a/b/c = 0/1/2, public a/b/c = 3/4/5) matches the original
  # _monolithic template so subnet CIDRs stay identical.
  subnet_newbits = 24 - tonumber(split("/", var.vpc_cidr_block)[1])
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
resource "aws_subnet" "private_subnet_a" {
  vpc_id            = aws_vpc.vpc.id
  availability_zone = "${data.aws_region.current.region}a"
  cidr_block        = cidrsubnet(var.vpc_cidr_block, local.subnet_newbits, 0)
  tags = merge(var.private_subnet_tags, {
    Name = join("-", [var.private_subnet_name, "a"])
  })
}
resource "aws_subnet" "private_subnet_b" {
  vpc_id            = aws_vpc.vpc.id
  availability_zone = "${data.aws_region.current.region}b"
  cidr_block        = cidrsubnet(var.vpc_cidr_block, local.subnet_newbits, 1)
  tags = merge(var.private_subnet_tags, {
    Name = join("-", [var.private_subnet_name, "b"])
  })
}
resource "aws_subnet" "private_subnet_c" {
  vpc_id            = aws_vpc.vpc.id
  availability_zone = "${data.aws_region.current.region}c"
  cidr_block        = cidrsubnet(var.vpc_cidr_block, local.subnet_newbits, 2)
  tags = merge(var.private_subnet_tags, {
    Name = join("-", [var.private_subnet_name, "c"])
  })
}
resource "aws_subnet" "public_subnet_a" {
  vpc_id                  = aws_vpc.vpc.id
  availability_zone       = "${data.aws_region.current.region}a"
  cidr_block              = cidrsubnet(var.vpc_cidr_block, local.subnet_newbits, 3)
  map_public_ip_on_launch = true
  tags = merge(var.public_subnet_tags, {
    Name = join("-", [var.public_subnet_name, "a"])
  })
}
resource "aws_subnet" "public_subnet_b" {
  vpc_id                  = aws_vpc.vpc.id
  availability_zone       = "${data.aws_region.current.region}b"
  cidr_block              = cidrsubnet(var.vpc_cidr_block, local.subnet_newbits, 4)
  map_public_ip_on_launch = true
  tags = merge(var.public_subnet_tags, {
    Name = join("-", [var.public_subnet_name, "b"])
  })
}
resource "aws_subnet" "public_subnet_c" {
  vpc_id                  = aws_vpc.vpc.id
  availability_zone       = "${data.aws_region.current.region}c"
  cidr_block              = cidrsubnet(var.vpc_cidr_block, local.subnet_newbits, 5)
  map_public_ip_on_launch = true
  tags = merge(var.public_subnet_tags, {
    Name = join("-", [var.public_subnet_name, "c"])
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
