# The client VPC: public subnets only, no private subnets and no NAT gateway.
#
# That asymmetry with the cluster VPC is deliberate and is what rules.md C-3 asks for - the zone and tier count
# is decided by what the project puts in the network, not by a house style:
#
#   - the only thing in this VPC is the workbench and the Lattice endpoint. The workbench needs a public address
#     to serve code-server, and the endpoint is reachable from anywhere in the VPC.
#   - nothing runs in a private subnet, so there is nothing for a NAT gateway to serve. A NAT gateway is billed
#     per hour whether or not traffic flows through it.
#   - the two VPCs are never routed to each other. That is the point of the project: the client reaches a private
#     API server through one Lattice endpoint rather than through peering or a transit gateway, so this VPC has
#     no route to the cluster's network at all.
resource "aws_vpc" "vpc" {
  cidr_block         = var.vpc_cidr_block
  enable_dns_support = true
  # Required rather than optional: a private hosted zone is only resolved inside a VPC that has DNS hostnames
  # and DNS support on, and the private zone is what makes the API server's name resolve here.
  enable_dns_hostnames = true
  tags = {
    Name = var.vpc_name
  }
}
# vpc_id on the gateway itself, rather than the separate aws_internet_gateway_attachment the conversion
# produced - the provider takes it here, which also removes the depends_on the original needed on its route.
resource "aws_internet_gateway" "internet_gateway" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = var.internet_gateway_name
  }
}
locals {
  subnets = {
    for index, suffix in var.availability_zone_suffixes : suffix => {
      availability_zone = "${var.region}${suffix}"
      cidr_block        = cidrsubnet(var.vpc_cidr_block, var.subnet_newbits, index)
    }
  }
}
resource "aws_subnet" "public" {
  for_each = local.subnets

  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = each.value.cidr_block
  availability_zone       = each.value.availability_zone
  map_public_ip_on_launch = true
  tags = {
    Name = "${var.public_subnet_name_prefix}-${each.key}"
  }
}
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = var.route_table_name
  }
}
resource "aws_route" "public_default" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.internet_gateway.id
}
resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  route_table_id = aws_route_table.public.id
  subnet_id      = each.value.id
}
