data "aws_region" "current" {}
locals {
  # Carves the VPC CIDR into /24s regardless of the VPC prefix length, so a
  # 10.0.0.0/16 VPC yields 10.0.0.0/24, 10.0.1.0/24, ... The index mapping below
  # (public a/b = 0/1, private a/b = 3/4) matches the original _monolithic
  # template so subnet CIDRs stay identical. Index 2 is deliberately skipped: the
  # CloudFormation AZ mapping carried a third zone that the stack never created,
  # and its public subnet held that slot.
  subnet_newbits = 24 - tonumber(split("/", var.vpc_cidr_block)[1])
  # The half of the Multus subnet that host-local hands to pods, carved here rather than
  # by the attachment module because the caller's VPC reservation has to name the same
  # block and has to exist before any node boots (rules.md B-5).
  #
  # Expressed as an offset into the subnet rather than as a CIDR of its own: a CIDR
  # written by hand can fall outside the subnet, and the failure - addresses that are not
  # routable on the ENI the attachment runs on - shows up as pods that come up with an
  # interface that reaches nothing (rules.md B-1).
  multus_pod_range_cidr = cidrsubnet(
    cidrsubnet(var.vpc_cidr_block, local.subnet_newbits, 5),
    var.multus_pod_range_newbits,
    var.multus_pod_range_index,
  )
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
# A subnet of its own for the Multus attachment, in the same zone as the node group's
# subnet - an ENI can be attached to an instance in another subnet only within one
# availability zone.
#
# This exists so that the addresses Multus hands to pods are not drawn from the same
# space as anything else. Sharing the node's private subnet, which is what the
# _monolithic template did, has two consequences that are not obvious:
#
#   - host-local writes the subnet it was given into the attachment, and ipvlan then
#     installs a link route for the whole of it on the pod's net1. Sharing the node's
#     subnet therefore makes a multi-homed pod send everything addressed to that
#     subnet - the node itself, every ordinary pod on it - out of net1, where only
#     same-node Multus peers answer. The VPC CNI path for that subnet is shadowed.
#   - the ENIs the node attaches take their own primary addresses out of the same
#     subnet, so one of them can land inside the range host-local hands to pods.
#
# Index 5 because 0/1 are the public subnets, 2 is the slot the _monolithic template
# skipped, and 3/4 are the private ones.
resource "aws_subnet" "multus_subnet_a" {
  vpc_id            = aws_vpc.vpc.id
  availability_zone = "${data.aws_region.current.region}a"
  cidr_block        = cidrsubnet(var.vpc_cidr_block, local.subnet_newbits, 5)
  tags = {
    Name = join("-", [var.multus_subnet_name, "a"])
  }
}
# Associated with the node subnet's route table, so this subnet behaves like any other
# private one. Multus traffic on net1 does not actually leave the node - the pod
# addresses are never assigned to the ENI, so the VPC cannot route them - but leaving a
# subnet on the VPC's main route table is a surprise waiting for whoever changes that.
resource "aws_route_table_association" "multus_subnet_a_route_table_association" {
  route_table_id = aws_route_table.private_subnet_a_route_table.id
  subnet_id      = aws_subnet.multus_subnet_a.id
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
