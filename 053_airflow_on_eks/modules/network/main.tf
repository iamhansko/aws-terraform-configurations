# The blueprint's VPC (vpc.tf in awslabs/data-on-eks@1b7906b8, schedulers/terraform/managed-airflow-mwaa),
# which it built with terraform-aws-modules/vpc. Rewritten as plain resources with the same layout:
#
#   - the first three availability zones the region offers;
#   - a private /20 per zone, carved from the start of the VPC range (cidrsubnet(vpc, 4, 0..2));
#   - a public /24 per zone, carved from index 48 on (cidrsubnet(vpc, 8, 48..50)), which is the first
#     /24 after the three /20s - so a 10.0.0.0/16 VPC gets 10.0.0.0/20, 10.0.16.0/20, 10.0.32.0/20
#     and 10.0.48.0/24, 10.0.49.0/24, 10.0.50.0/24;
#   - one NAT gateway (single_nat_gateway = true) and one private route table shared by the three
#     private subnets.
#
# Three zones because the cluster's node group spans them and the cluster autoscaler adds nodes
# across them; MWAA uses the first two private subnets, which is the number it requires (rules.md
# C-3). One NAT gateway rather than one per zone, as the blueprint chose: a zone outage takes egress
# away from the other two zones' private subnets, which a demo can live with and which saves two
# NAT gateways billed by the hour.
#
# The workbench instance sits in a public subnet of this same VPC. Before the blueprint was embedded
# here it had a one-subnet VPC of its own, because the cluster lived in a VPC this configuration never
# saw; now that the cluster's VPC is in this state, a second VPC would only be a second network to
# keep apart from the first, and the workbench could no longer reach the API server's private
# endpoint.
#
# Not reproduced: manage_default_network_acl, manage_default_route_table and
# manage_default_security_group. The blueprint turned them on to put Name tags on the VPC's default
# objects ("Manage so we can name"); nothing here uses any of the three.
data "aws_availability_zones" "available" {
  state = "available"
  # Standard zones only. Local Zones and Wavelength Zones are opt-in, and a subnet there cannot host
  # EKS control plane ENIs or MWAA.
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}
locals {
  # slice(), as the blueprint did. The names come back sorted, so the same three zones are chosen on
  # every plan; a region with fewer than three standard zones fails here at plan rather than halfway
  # through apply.
  zones = slice(data.aws_availability_zones.available.names, 0, 3)
  # Keyed by zone name: the zone is what makes each subnet distinct, and a key that is a list index
  # would renumber every subnet after it if the list ever changed.
  zone_index = { for index, zone in local.zones : zone => index }
}
resource "aws_vpc" "vpc" {
  cidr_block = var.vpc_cidr_block
  # Both true, as terraform-aws-modules/vpc defaults them. Not variables: the EKS private endpoint is
  # only resolvable inside the VPC with both on, and that is the address MWAA's workers and the nodes
  # use to reach the API server (rules.md B-1, on making a wrong value unrepresentable).
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = var.name
  }
}
# vpc_id on the gateway itself rather than a separate aws_internet_gateway_attachment. The gateway is
# then attached before it counts as created, so the route and the NAT gateway below - which refer to
# it - cannot be sent ahead of the attachment.
resource "aws_internet_gateway" "internet_gateway" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = var.name
  }
}
resource "aws_subnet" "public" {
  for_each = local.zone_index

  vpc_id            = aws_vpc.vpc.id
  availability_zone = each.key
  cidr_block        = cidrsubnet(var.vpc_cidr_block, 8, each.value + 48)
  # The workbench asks for a public address itself; this is what the NAT gateway's subnet and anything
  # else launched here get, and the route to the internet gateway only carries traffic for an
  # address that is public.
  map_public_ip_on_launch = true
  tags = merge(var.public_subnet_tags, {
    Name = "${var.name}-public-${each.key}"
  })
}
resource "aws_subnet" "private" {
  for_each = local.zone_index

  vpc_id            = aws_vpc.vpc.id
  availability_zone = each.key
  cidr_block        = cidrsubnet(var.vpc_cidr_block, 4, each.value)
  tags = merge(var.private_subnet_tags, {
    Name = "${var.name}-private-${each.key}"
  })
}
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = "${var.name}-public"
  }
}
resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.internet_gateway.id
}
resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  route_table_id = aws_route_table.public.id
  subnet_id      = each.value.id
}
resource "aws_eip" "nat_gateway" {
  domain = "vpc"
  tags = {
    Name = "${var.name}-${local.zones[0]}"
  }
}
# In the first zone's public subnet, as single_nat_gateway placed it.
resource "aws_nat_gateway" "nat_gateway" {
  allocation_id = aws_eip.nat_gateway.allocation_id
  subnet_id     = aws_subnet.public[local.zones[0]].id
  tags = {
    Name = "${var.name}-${local.zones[0]}"
  }
  # A public NAT gateway needs the internet gateway attached to pass traffic, and nothing above
  # references one from the other (rules.md D-1).
  depends_on = [aws_internet_gateway.internet_gateway]
}
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = "${var.name}-private"
  }
}
resource "aws_route" "private_nat" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat_gateway.id
}
resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private

  route_table_id = aws_route_table.private.id
  subnet_id      = each.value.id
}
