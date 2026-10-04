locals {
  # One subnet per zone in each tier, keyed by the zone suffix rather than indexed. for_each over a set of
  # literal suffixes, so adding a zone does not renumber the others (rules.md B-8 is the same argument about
  # keys, applied to a static list).
  #
  # The CIDRs are derived from the VPC's own block rather than listed literally as the _monolithic template's
  # AzMapping did. That mapping hardcoded 10.1.0.0/24 through 10.1.3.0/24, so a different vpc_cidr_block
  # produced subnets outside the VPC and the failure was an InvalidSubnet error with no hint of where the
  # numbers came from.
  public_subnets = {
    for index, suffix in var.availability_zone_suffixes : suffix => {
      availability_zone = "${var.region}${suffix}"
      cidr_block        = cidrsubnet(var.vpc_cidr_block, var.subnet_newbits, index)
    }
  }
  private_subnets = {
    for index, suffix in var.availability_zone_suffixes : suffix => {
      availability_zone = "${var.region}${suffix}"
      cidr_block        = cidrsubnet(var.vpc_cidr_block, var.subnet_newbits, index + var.private_subnet_index_offset)
    }
  }
}
resource "aws_vpc" "vpc" {
  cidr_block           = var.vpc_cidr_block
  enable_dns_support   = var.enable_dns_support
  enable_dns_hostnames = var.enable_dns_hostnames
  tags = {
    Name = var.vpc_name
  }
}
# vpc_id on the gateway itself, rather than the separate aws_internet_gateway_attachment the conversion
# produced. CloudFormation models the gateway and its attachment as two resources; Terraform's provider takes
# vpc_id here, and the separate attachment resource then has nothing to do - which also removes the depends_on
# the original needed on its route.
resource "aws_internet_gateway" "internet_gateway" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = var.internet_gateway_name
  }
}
resource "aws_subnet" "public" {
  for_each = local.public_subnets

  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = each.value.cidr_block
  availability_zone       = each.value.availability_zone
  map_public_ip_on_launch = true
  tags = merge(var.public_subnet_tags, {
    Name = "${var.public_subnet_name_prefix}-${each.key}"
  })
}
resource "aws_subnet" "private" {
  for_each = local.private_subnets

  vpc_id            = aws_vpc.vpc.id
  cidr_block        = each.value.cidr_block
  availability_zone = each.value.availability_zone
  tags = merge(var.private_subnet_tags, {
    Name = "${var.private_subnet_name_prefix}-${each.key}"
  })
}
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = var.public_route_table_name
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
# One Elastic IP per zone the NAT gateway is given an address in, and no more. Deriving these from
# nat_availability_zone_suffixes makes an allocated-but-unrouted address unreachable as a state.
resource "aws_eip" "nat" {
  for_each = toset(var.nat_availability_zone_suffixes)

  tags = {
    Name = "${var.nat_gateway_name}-${each.key}"
  }

  # An address allocated before the gateway exists is fine; one allocated in a VPC with no internet gateway
  # cannot be associated. Referencing nothing would leave the order to chance (rules.md D-1).
  depends_on = [aws_internet_gateway.internet_gateway]
}
# A regional NAT gateway, as the _monolithic template had it (AvailabilityMode: regional with one
# AvailabilityZoneAddresses entry per zone).
#
# The difference from the usual arrangement is worth knowing: a zonal NAT gateway lives in one subnet, and a
# private subnet in another zone reaches it over a cross-zone hop that is billed both ways - which is why the
# usual advice is one gateway per zone. A regional gateway is a single resource serving every zone, with an
# address in each zone listed below, so it is cheaper than one gateway per zone and still keeps traffic in-zone
# for the zones it has addresses in.
#
# This project needs the egress: the nodes are in private subnets and pull the controller image and the
# container images for the demo workload from the internet. Only the EKS API server is private here.
resource "aws_nat_gateway" "nat_gateway" {
  vpc_id            = aws_vpc.vpc.id
  availability_mode = "regional"

  dynamic "availability_zone_address" {
    for_each = toset(var.nat_availability_zone_suffixes)
    content {
      availability_zone = "${var.region}${availability_zone_address.value}"
      allocation_ids    = [aws_eip.nat[availability_zone_address.value].allocation_id]
    }
  }

  tags = {
    Name = var.nat_gateway_name
  }

  # The gateway needs a route to the internet through the VPC's own gateway before it works, and nothing in its
  # arguments references it (rules.md D-1).
  depends_on = [aws_internet_gateway.internet_gateway]
}
# One private route table for every private subnet, which is what a regional NAT gateway allows - with zonal
# gateways this would have to be one table per zone, each pointing at its own gateway.
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = var.private_route_table_name
  }
}
resource "aws_route" "private_default" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat_gateway.id
}
resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private

  route_table_id = aws_route_table.private.id
  subnet_id      = each.value.id
}
