data "aws_region" "current" {}
locals {
  # Carves the VPC CIDR into /24s regardless of the VPC prefix length, so a
  # 10.0.0.0/16 VPC yields 10.0.0.0/24, 10.0.1.0/24, ... The index mapping below
  # (public a/b = 0/1, private a/b = 3/4) matches the original _monolithic
  # template so subnet CIDRs stay identical. Index 2 is deliberately skipped: the
  # CloudFormation AZ mapping carried a third zone that the stack never created,
  # and its public subnet held that slot.
  subnet_newbits = 24 - tonumber(split("/", var.vpc_cidr_block)[1])
  # The same /24 carving applied to the secondary range, so a 100.64.0.0/16
  # secondary CIDR yields 100.64.0.0/24 and 100.64.1.0/24 - the two the
  # _monolithic template created. Computed separately because the secondary block
  # can have a different prefix length from the primary one.
  pod_subnet_newbits = var.secondary_cidr_block == null ? 0 : 24 - tonumber(split("/", var.secondary_cidr_block)[1])
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
# A NAT gateway per zone, and a private route table per zone pointing at it, so
# a zone failure cannot take out egress for the other zone's private subnet.
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
# --- Custom networking: a second CIDR that pods live in ---
#
# This is what the project is about. The VPC's primary range is a /16 of RFC 1918
# space, and it runs out fast when every pod takes an address from it. A second
# CIDR carries the pods instead, so pod addresses come from 100.64.0.0/16 - CGNAT
# space, which does not have to be unique across peered or on-premises networks -
# while nodes keep their addresses in the primary range.
#
# The VPC CNI does not discover these subnets. It reads ENIConfig custom resources,
# one per availability zone, which is why this module also exposes the pod subnets
# keyed by zone.
resource "aws_vpc_ipv4_cidr_block_association" "secondary" {
  count = var.secondary_cidr_block == null ? 0 : 1

  vpc_id     = aws_vpc.vpc.id
  cidr_block = var.secondary_cidr_block
}
# A subnet in the secondary range cannot be created until the association exists,
# and the association is not referenced by the subnet's arguments - the CIDR is a
# literal derived from a variable - so nothing else expresses that ordering
# (rules.md D-1).
resource "aws_subnet" "pod_subnet_a" {
  count = var.secondary_cidr_block == null ? 0 : 1

  vpc_id            = aws_vpc.vpc.id
  cidr_block        = cidrsubnet(var.secondary_cidr_block, local.pod_subnet_newbits, 0)
  availability_zone = "${data.aws_region.current.region}a"

  tags = merge(var.pod_subnet_tags, {
    Name = join("-", [var.pod_subnet_name, "a"])
  })

  depends_on = [aws_vpc_ipv4_cidr_block_association.secondary]
}
resource "aws_subnet" "pod_subnet_b" {
  count = var.secondary_cidr_block == null ? 0 : 1

  vpc_id            = aws_vpc.vpc.id
  cidr_block        = cidrsubnet(var.secondary_cidr_block, local.pod_subnet_newbits, 1)
  availability_zone = "${data.aws_region.current.region}b"

  tags = merge(var.pod_subnet_tags, {
    Name = join("-", [var.pod_subnet_name, "b"])
  })

  depends_on = [aws_vpc_ipv4_cidr_block_association.secondary]
}
# A route table per pod subnet, per zone, for the same reason the private subnets
# have one each: a zone's egress should not depend on another zone's NAT gateway.
resource "aws_route_table" "pod_subnet_a_route_table" {
  count = var.secondary_cidr_block == null ? 0 : 1

  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = join("-", [var.pod_route_table_name, "a"])
  }
}
resource "aws_route_table_association" "pod_subnet_a_route_table_association" {
  count = var.secondary_cidr_block == null ? 0 : 1

  route_table_id = aws_route_table.pod_subnet_a_route_table[0].id
  subnet_id      = aws_subnet.pod_subnet_a[0].id
}
# The _monolithic template created the pod route tables and then never added a
# route to them, so pods had no path off the VPC at all. That is survivable for a
# workload that only serves inbound traffic - the kubelet pulls images over the
# node's primary interface, which is in a private subnet with NAT - but a pod
# calling anything external fails, and it fails as a timeout with nothing pointing
# at routing. AWS's own custom networking guidance attaches the pod subnets to a
# NAT route, so that is the default here (rules.md B-4 for the switch).
resource "aws_route" "pod_subnet_a_route" {
  count = var.secondary_cidr_block != null && var.enable_pod_subnet_nat_route ? 1 : 0

  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat_gateway_a.id
  route_table_id         = aws_route_table.pod_subnet_a_route_table[0].id
}
resource "aws_route_table" "pod_subnet_b_route_table" {
  count = var.secondary_cidr_block == null ? 0 : 1

  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = join("-", [var.pod_route_table_name, "b"])
  }
}
resource "aws_route_table_association" "pod_subnet_b_route_table_association" {
  count = var.secondary_cidr_block == null ? 0 : 1

  route_table_id = aws_route_table.pod_subnet_b_route_table[0].id
  subnet_id      = aws_subnet.pod_subnet_b[0].id
}
resource "aws_route" "pod_subnet_b_route" {
  count = var.secondary_cidr_block != null && var.enable_pod_subnet_nat_route ? 1 : 0

  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat_gateway_b.id
  route_table_id         = aws_route_table.pod_subnet_b_route_table[0].id
}
