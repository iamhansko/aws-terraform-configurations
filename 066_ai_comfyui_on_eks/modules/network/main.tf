# The VPC the whole project runs in - the cluster, its nodes, the internal ALB and the workbench.
#
# This replaces two networks. The _monolithic template built a one-subnet VPC for the workbench and nothing
# else, because the blueprint the workbench deployed then built its own three-zone VPC (ComfyuiVPC) through
# CDK. With the blueprint's resources declared here, there is one VPC, laid out the way ComfyuiVPC was:
# three zones, a public and a private /20 in each, egress through NAT, and an S3 gateway endpoint.
locals {
  # One subnet per zone in each tier, keyed by the zone suffix rather than indexed. for_each over a set of
  # literal suffixes, so adding a zone does not renumber the others - which an index-based count would
  # (rules.md B-8 is the same argument about keys, applied to a static list).
  #
  # The CIDRs are derived from the VPC's own block, in the order CDK allocated them: every public subnet
  # first, then every private one.
  public_subnets = {
    for index, suffix in var.availability_zone_suffixes : suffix => {
      availability_zone = "${var.region}${suffix}"
      cidr_block        = cidrsubnet(var.vpc_cidr_block, var.public_subnet_newbits, index)
    }
  }
  private_subnets = {
    for index, suffix in var.availability_zone_suffixes : suffix => {
      availability_zone = "${var.region}${suffix}"
      cidr_block        = cidrsubnet(var.vpc_cidr_block, var.public_subnet_newbits, index + var.private_subnet_index_offset)
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
# One Elastic IP per zone the NAT gateway is given an address in, and no more.
resource "aws_eip" "nat" {
  for_each = toset(var.nat_availability_zone_suffixes)

  tags = {
    Name = "${var.nat_gateway_name}-${each.key}"
  }

  # An address allocated in a VPC with no internet gateway cannot be associated, and referencing nothing would
  # leave the order to chance.
  depends_on = [aws_internet_gateway.internet_gateway]
}
# A regional NAT gateway rather than the blueprint's three zonal ones (natGateways: 3).
#
# The egress path is the same: with an address in every zone, each private subnet leaves through its own zone,
# which is what one gateway per zone was for. The difference is that this is one resource serving every zone,
# so the private subnets share one route table instead of needing one table per zone pointing at its own
# gateway.
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

  # The gateway needs the VPC's internet gateway before it works, and nothing in its arguments references it
  # (rules.md D-1).
  depends_on = [aws_internet_gateway.internet_gateway]
}
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
# The blueprint's gatewayEndpoints.s3. On the private route table only, which is where everything that reads
# models lives - the GPU nodes copying them at boot, the sync Lambda's commands on those nodes, and the
# Mountpoint driver behind the input and output volumes. The workbench in a public subnet reaches S3 through
# the internet gateway, which costs nothing either way.
resource "aws_vpc_endpoint" "s3" {
  count = var.create_s3_gateway_endpoint ? 1 : 0

  vpc_id            = aws_vpc.vpc.id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]

  tags = {
    Name = "${var.vpc_name}-s3"
  }
}
