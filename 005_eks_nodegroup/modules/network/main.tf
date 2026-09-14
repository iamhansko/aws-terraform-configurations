data "aws_region" "current" {}

locals {
  subnet_newbits = 24 - tonumber(split("/", var.vpc_cidr_block)[1])
}

resource "aws_vpc" "vpc" {
  enable_dns_hostnames = true
  cidr_block           = var.vpc_cidr_block
  tags = {
    Name = var.vpc_name
  }
}

resource "aws_subnet" "private_subnet_a" {
  availability_zone = "${data.aws_region.current.region}a"
  cidr_block        = cidrsubnet(var.vpc_cidr_block, local.subnet_newbits, 0)
  tags = {
    Name                              = join("-", [var.private_subnet_name, "a"])
    "kubernetes.io/role/internal-elb" = 1
  }
  vpc_id = aws_vpc.vpc.id
}

resource "aws_subnet" "private_subnet_b" {
  availability_zone = "${data.aws_region.current.region}b"
  cidr_block        = cidrsubnet(var.vpc_cidr_block, local.subnet_newbits, 1)
  tags = {
    Name                              = join("-", [var.private_subnet_name, "b"])
    "kubernetes.io/role/internal-elb" = 1
  }
  vpc_id = aws_vpc.vpc.id
}

resource "aws_subnet" "private_subnet_c" {
  availability_zone = "${data.aws_region.current.region}c"
  cidr_block        = cidrsubnet(var.vpc_cidr_block, local.subnet_newbits, 2)
  tags = {
    Name                              = join("-", [var.private_subnet_name, "c"])
    "kubernetes.io/role/internal-elb" = 1
  }
  vpc_id = aws_vpc.vpc.id
}

resource "aws_subnet" "public_subnet_a" {
  availability_zone = "${data.aws_region.current.region}a"
  cidr_block        = cidrsubnet(var.vpc_cidr_block, local.subnet_newbits, 3)
  tags = {
    Name                     = join("-", [var.public_subnet_name, "a"])
    "kubernetes.io/role/elb" = 1
  }
  vpc_id = aws_vpc.vpc.id
}

resource "aws_subnet" "public_subnet_b" {
  availability_zone = "${data.aws_region.current.region}b"
  cidr_block        = cidrsubnet(var.vpc_cidr_block, local.subnet_newbits, 4)
  tags = {
    Name                     = join("-", [var.public_subnet_name, "b"])
    "kubernetes.io/role/elb" = 1
  }
  vpc_id = aws_vpc.vpc.id
}

resource "aws_subnet" "public_subnet_c" {
  availability_zone = "${data.aws_region.current.region}c"
  cidr_block        = cidrsubnet(var.vpc_cidr_block, local.subnet_newbits, 5)
  tags = {
    Name                     = join("-", [var.public_subnet_name, "c"])
    "kubernetes.io/role/elb" = 1
  }
  vpc_id = aws_vpc.vpc.id
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

resource "aws_eip" "nat_gateway_a_elastic_ip" {}

resource "aws_nat_gateway" "nat_gateway_a" {
  allocation_id = aws_eip.nat_gateway_a_elastic_ip.allocation_id
  subnet_id     = aws_subnet.public_subnet_a.id
  tags = {
    Name = join("-", [var.nat_gateway_name, "a"])
  }
}

resource "aws_eip" "nat_gateway_b_elastic_ip" {}

resource "aws_nat_gateway" "nat_gateway_b" {
  allocation_id = aws_eip.nat_gateway_b_elastic_ip.allocation_id
  subnet_id     = aws_subnet.public_subnet_b.id
  tags = {
    Name = join("-", [var.nat_gateway_name, "b"])
  }
}

resource "aws_eip" "nat_gateway_c_elastic_ip" {}

resource "aws_nat_gateway" "nat_gateway_c" {
  allocation_id = aws_eip.nat_gateway_c_elastic_ip.allocation_id
  subnet_id     = aws_subnet.public_subnet_c.id
  tags = {
    Name = join("-", [var.nat_gateway_name, "c"])
  }
}

resource "aws_route_table" "public_subnet_route_table" {
  tags = {
    Name = join("-", [var.public_subnet_name, "rt"])
  }
  vpc_id = aws_vpc.vpc.id
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

resource "aws_route" "public_subnet_route" {
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.internet_gateway.id
  route_table_id         = aws_route_table.public_subnet_route_table.id
}

resource "aws_route_table" "private_subnet_a_route_table" {
  tags = {
    Name = join("-", [var.private_subnet_name, "a", "rt"])
  }
  vpc_id = aws_vpc.vpc.id
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

resource "aws_route_table" "private_subnet_b_route_table" {
  tags = {
    Name = join("-", [var.private_subnet_name, "b", "rt"])
  }
  vpc_id = aws_vpc.vpc.id
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

resource "aws_route_table" "private_subnet_c_route_table" {
  tags = {
    Name = join("-", [var.private_subnet_name, "c", "rt"])
  }
  vpc_id = aws_vpc.vpc.id
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
