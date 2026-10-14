# VPC Block Public Access in block-ingress mode permits outbound internet sessions through NAT gateways but
# blocks direct public-instance/IGW traffic. Keep the one-AZ demo topology, place only the NAT gateway in the
# public subnet, and launch the one-shot bootstrap instance in a private subnet (rules.md C-3/D-3).
resource "aws_vpc" "vpc" {
  cidr_block           = var.vpc_cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true

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

resource "aws_subnet" "public_subnet_a" {
  vpc_id                  = aws_vpc.vpc.id
  availability_zone       = var.availability_zone
  cidr_block              = cidrsubnet(var.vpc_cidr_block, 24 - tonumber(split("/", var.vpc_cidr_block)[1]), 0)
  map_public_ip_on_launch = true

  tags = {
    Name = var.public_subnet_name
  }
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

  depends_on = [aws_internet_gateway_attachment.vpc_internet_gateway_attachment]
}

resource "aws_route_table_association" "public_subnet_a_route_table_association" {
  route_table_id = aws_route_table.public_subnet_route_table.id
  subnet_id      = aws_subnet.public_subnet_a.id
}

resource "aws_eip" "nat_gateway" {
  domain = "vpc"

  tags = {
    Name = var.nat_eip_name
  }
}

resource "aws_nat_gateway" "bootstrap" {
  allocation_id = aws_eip.nat_gateway.id
  subnet_id     = aws_subnet.public_subnet_a.id

  tags = {
    Name = var.nat_gateway_name
  }

  # The NAT gateway must have an attached IGW and an active public default route before private egress uses it.
  depends_on = [aws_route.public_subnet_route]
}

resource "aws_subnet" "private_subnet_a" {
  vpc_id                  = aws_vpc.vpc.id
  availability_zone       = var.availability_zone
  cidr_block              = cidrsubnet(var.vpc_cidr_block, 24 - tonumber(split("/", var.vpc_cidr_block)[1]), 1)
  map_public_ip_on_launch = false

  tags = {
    Name = var.private_subnet_name
  }
}

resource "aws_route_table" "private_subnet_route_table" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = var.private_route_table_name
  }
}

resource "aws_route" "private_subnet_route" {
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.bootstrap.id
  route_table_id         = aws_route_table.private_subnet_route_table.id
}

resource "aws_route_table_association" "private_subnet_a_route_table_association" {
  route_table_id = aws_route_table.private_subnet_route_table.id
  subnet_id      = aws_subnet.private_subnet_a.id
}
