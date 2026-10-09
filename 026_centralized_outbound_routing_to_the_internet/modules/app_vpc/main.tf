# The VPC whose traffic this project centralizes, and the interesting thing about it is what it does
# not contain: no internet gateway, no NAT gateway, no public subnet, no Elastic IP. Every one of
# those lives in the egress VPC. The only way out of here is the transit gateway, which is what makes
# the egress path testable at all - if the route to the gateway is wrong there is no second path to
# fall back on, so the demo fails visibly rather than quietly working for the wrong reason.
locals {
  private_subnets = {
    for suffix in var.availability_zone_suffixes : suffix => {
      availability_zone = "${var.region}${suffix}"
      cidr_block        = var.private_subnet_cidr_blocks[suffix]
    }
  }
}
resource "aws_vpc" "app_vpc" {
  cidr_block = var.vpc_cidr_block
  # Both on, as the _monolithic template had them. enable_dns_support is what gives hosts here the
  # Amazon-provided resolver at the VPC+2 address. That resolver answers inside the VPC, so it is not
  # affected by the firewall's rule against DNS leaving - which is exactly why the probe in the root's
  # outputs queries an external resolver instead.
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "${var.name}-vpc"
  }
}
resource "aws_subnet" "private" {
  for_each = local.private_subnets

  vpc_id            = aws_vpc.app_vpc.id
  availability_zone = each.value.availability_zone
  cidr_block        = each.value.cidr_block
  # map_public_ip_on_launch left at its default of false, as the _monolithic template had it. Setting
  # it would hand instances here a public address that nothing can route to, since this VPC has no
  # internet gateway - which looks like working internet access until something tries to use it.
  tags = {
    Name = "${var.name}-private-${each.key}"
  }
}
# One route table for both subnets, as the _monolithic template had it (app-rt). Unlike the egress
# VPC's attachment tables this one can be shared, because the single route the root writes into it
# points at the transit gateway, and a transit gateway is not zonal - the attachment ENI in the
# packet's own zone is the one that picks it up.
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.app_vpc.id
  tags = {
    Name = "${var.name}-rt"
  }
}
# The default route out of this table is not here. It points at the transit gateway, so it needs both
# this table and the gateway, and the root is where two modules are joined (rules.md C-1). It is
# aws_route.app_default_to_transit_gateway in the root's main.tf, and without it this table holds
# only the VPC's local route and nothing here reaches anything.
resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}
