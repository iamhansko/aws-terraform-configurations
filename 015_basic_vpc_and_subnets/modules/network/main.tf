data "aws_region" "current" {}
locals {
  # Carves the VPC CIDR into /24s regardless of the VPC prefix length, so a
  # 10.1.0.0/16 VPC yields 10.1.0.0/24, 10.1.1.0/24, ... The index mapping below
  # (public a/b = 0/1, private a/b = 2/3) matches the original _monolithic
  # template so subnet CIDRs stay identical.
  #
  # The _monolithic version wrote this as
  #   element([for __i in range(4) : cidrsubnet(cidr, 32 - 8 - tonumber(...)), __i)], 0)
  # which built all four CIDRs in every subnet just to take one of them, with the
  # /24 hidden inside "32 - 8". Naming the newbits once says the same thing and is
  # the only place to change if the subnet size ever does.
  subnet_newbits = 24 - tonumber(split("/", var.vpc_cidr_block)[1])
}
# Two availability zones rather than the three the EKS projects in this
# repository use. Three is a requirement of EKS control plane placement, not of a
# VPC, and each zone here costs a NAT gateway - so this project spans the two the
# _monolithic template had.
resource "aws_vpc" "vpc" {
  cidr_block = var.vpc_cidr_block
  # Neither of these was in the _monolithic template, which left them at the
  # account defaults (support on, hostnames off). They are named here because
  # this project exists to show what a usable VPC is made of, and a private
  # subnet whose instances cannot resolve names is not one.
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
# The gateway and its attachment stay two resources, as the CloudFormation stack
# had them, rather than collapsing into vpc_id on the gateway itself. Both shapes
# work; keeping them apart makes the attachment visible in the plan as its own
# step, which is what the public route below actually waits for.
resource "aws_internet_gateway_attachment" "vpc_internet_gateway_attachment" {
  internet_gateway_id = aws_internet_gateway.internet_gateway.id
  vpc_id              = aws_vpc.vpc.id
}
# One route table shared by both public subnets: they differ only in which zone
# they are in, and the route out is the same gateway for both.
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

  # Referencing the gateway's ID orders this after the gateway, but not after the
  # attachment - and a route to a gateway that is not attached to this VPC yet is
  # rejected. Nothing else expresses that, so it is spelled out (rules.md D-1).
  depends_on = [aws_internet_gateway_attachment.vpc_internet_gateway_attachment]
}
resource "aws_subnet" "public_subnet_a" {
  vpc_id                  = aws_vpc.vpc.id
  availability_zone       = "${data.aws_region.current.region}a"
  cidr_block              = cidrsubnet(var.vpc_cidr_block, local.subnet_newbits, 0)
  map_public_ip_on_launch = var.map_public_ip_on_launch
  tags = merge(var.public_subnet_tags, {
    Name = join("-", [var.public_subnet_name, "a"])
  })
}
resource "aws_subnet" "public_subnet_b" {
  vpc_id                  = aws_vpc.vpc.id
  availability_zone       = "${data.aws_region.current.region}b"
  cidr_block              = cidrsubnet(var.vpc_cidr_block, local.subnet_newbits, 1)
  map_public_ip_on_launch = var.map_public_ip_on_launch
  tags = merge(var.public_subnet_tags, {
    Name = join("-", [var.public_subnet_name, "b"])
  })
}
resource "aws_subnet" "private_subnet_a" {
  vpc_id            = aws_vpc.vpc.id
  availability_zone = "${data.aws_region.current.region}a"
  cidr_block        = cidrsubnet(var.vpc_cidr_block, local.subnet_newbits, 2)
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
resource "aws_route_table_association" "public_subnet_a_route_table_association" {
  route_table_id = aws_route_table.public_subnet_route_table.id
  subnet_id      = aws_subnet.public_subnet_a.id
}
resource "aws_route_table_association" "public_subnet_b_route_table_association" {
  route_table_id = aws_route_table.public_subnet_route_table.id
  subnet_id      = aws_subnet.public_subnet_b.id
}
# A NAT gateway per zone, and a private route table per zone pointing at it, so a
# zone failure cannot take out egress for the other zone's private subnet. The
# cheaper alternative - one NAT gateway shared by both private subnets - is also
# the one where losing a zone takes the surviving subnet's internet access with
# it, because its only route out lives in the failed zone.
resource "aws_eip" "nat_gateway_a_elastic_ip" {
  # Not in the _monolithic template, which relied on the provider's default. EC2
  # Classic is gone, so vpc is the only meaningful value, but naming it keeps the
  # plan from being read as "domain unset, hope for the best".
  domain = "vpc"
  tags = {
    Name = join("-", [var.nat_gateway_name, "a", "eip"])
  }
}
resource "aws_nat_gateway" "nat_gateway_a" {
  allocation_id = aws_eip.nat_gateway_a_elastic_ip.allocation_id
  subnet_id     = aws_subnet.public_subnet_a.id
  tags = {
    Name = join("-", [var.nat_gateway_name, "a"])
  }

  # A NAT gateway needs a route to the internet from the subnet it sits in, and
  # it is created before that route exists unless told otherwise. Its own subnet
  # reference only orders it after the subnet, not after the subnet's route out
  # (rules.md D-1).
  depends_on = [aws_route.public_subnet_route]
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
resource "aws_eip" "nat_gateway_b_elastic_ip" {
  domain = "vpc"
  tags = {
    Name = join("-", [var.nat_gateway_name, "b", "eip"])
  }
}
resource "aws_nat_gateway" "nat_gateway_b" {
  allocation_id = aws_eip.nat_gateway_b_elastic_ip.allocation_id
  subnet_id     = aws_subnet.public_subnet_b.id
  tags = {
    Name = join("-", [var.nat_gateway_name, "b"])
  }

  # Same reasoning as nat_gateway_a (rules.md D-1).
  depends_on = [aws_route.public_subnet_route]
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
