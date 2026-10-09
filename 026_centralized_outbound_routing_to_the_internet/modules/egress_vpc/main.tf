locals {
  # Three subnet tiers per zone, and which tier a thing sits in is the whole design.
  #
  #   public      Holds a NAT gateway per zone. The only tier with a route to the internet gateway,
  #               and therefore the only place in either VPC where a packet can leave.
  #   attachment  Holds the transit gateway attachment's ENI per zone. Traffic from the app VPC
  #               arrives here, and the route table on this tier is what sends it onward to a NAT
  #               gateway. The _monolithic template called these the peering subnets.
  #   firewall    Holds a Network Firewall endpoint per zone. AWS allows nothing else in a firewall
  #               subnet. These get no route table association - see modules/network_firewall.
  #
  # Keyed by zone suffix rather than built as a list, because every route table, NAT gateway and
  # association below has to pair with the subnet in its own zone. A list would make that pairing
  # positional, and a reordered list would silently point a zone's traffic at another zone's NAT
  # gateway - which works, costs cross-zone data transfer on every byte, and shows up nowhere.
  public_subnets = {
    for suffix in var.availability_zone_suffixes : suffix => {
      availability_zone = "${var.region}${suffix}"
      cidr_block        = var.public_subnet_cidr_blocks[suffix]
    }
  }
  attachment_subnets = {
    for suffix in var.availability_zone_suffixes : suffix => {
      availability_zone = "${var.region}${suffix}"
      cidr_block        = var.attachment_subnet_cidr_blocks[suffix]
    }
  }
  firewall_subnets = {
    for suffix in var.availability_zone_suffixes : suffix => {
      availability_zone = "${var.region}${suffix}"
      cidr_block        = var.firewall_subnet_cidr_blocks[suffix]
    }
  }
}
resource "aws_vpc" "egress_vpc" {
  cidr_block = var.vpc_cidr_block
  # Both on, as the _monolithic template had them. enable_dns_support is what puts the
  # Amazon-provided resolver at the VPC+2 address, and that matters more here than usual: the
  # firewall's stateful rule group drops DNS leaving the VPC, so a host that could not use the
  # internal resolver would have no name resolution at all.
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "${var.name}-vpc"
  }
}
# The gateway and its attachment as two resources, which is how CloudFormation models it
# (AWS::EC2::InternetGateway plus AWS::EC2::VPCGatewayAttachment) and how the _monolithic file
# converted it. Terraform's aws_internet_gateway also accepts vpc_id directly, which collapses the
# pair into one resource; the split is kept here because it is what the original had, and because
# the route below then has to say out loud what it depends on.
resource "aws_internet_gateway" "egress_igw" {
  tags = {
    Name = "${var.name}-igw"
  }
}
resource "aws_internet_gateway_attachment" "egress_igw_attachment" {
  vpc_id              = aws_vpc.egress_vpc.id
  internet_gateway_id = aws_internet_gateway.egress_igw.id
}
resource "aws_subnet" "public" {
  for_each = local.public_subnets

  vpc_id            = aws_vpc.egress_vpc.id
  availability_zone = each.value.availability_zone
  cidr_block        = each.value.cidr_block
  # On, as the _monolithic template had it. Nothing is launched into these subnets by this project -
  # the NAT gateways carry their own Elastic IPs - so this only affects anything added later.
  map_public_ip_on_launch = true
  tags = {
    Name = "${var.name}-public-${each.key}"
  }
}
resource "aws_subnet" "attachment" {
  for_each = local.attachment_subnets

  vpc_id            = aws_vpc.egress_vpc.id
  availability_zone = each.value.availability_zone
  cidr_block        = each.value.cidr_block
  tags = {
    Name = "${var.name}-tgw-attach-${each.key}"
  }
}
resource "aws_subnet" "firewall" {
  for_each = local.firewall_subnets

  vpc_id            = aws_vpc.egress_vpc.id
  availability_zone = each.value.availability_zone
  cidr_block        = each.value.cidr_block
  tags = {
    Name = "${var.name}-firewall-${each.key}"
  }
}
# One public route table for both zones, as the _monolithic template had it. That is fine for the
# two routes on it - an internet gateway is not zonal, and the return route to the app VPC points at
# a transit gateway, which is not zonal either.
#
# It would stop being fine the moment the firewall is put in the data path, because a firewall
# endpoint is zonal: a single shared table can only name one of them, so one zone's return traffic
# would be inspected by the other zone's endpoint. Network Firewall's stateful engine sees one
# direction of such a flow and drops it. That is the first thing to change if the routes described in
# modules/network_firewall/main.tf are ever added.
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.egress_vpc.id
  tags = {
    Name = "${var.name}-public-rt"
  }
}
# Route 1 of 6. Everything not local leaves through the internet gateway.
#
# What uses it: the NAT gateways, which sit in these subnets. Nothing else in either VPC has a route
# to an internet gateway, so this one route is the only exit from the whole project.
#
# Missing: both NAT gateways come up healthy and translate addresses to nowhere. Every connection
# from the app VPC times out, apply reports success, and nothing logs a reason.
resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = var.default_route_cidr_block
  gateway_id             = aws_internet_gateway.egress_igw.id

  # gateway_id refers to the gateway, so Terraform orders this after the gateway and not after the
  # attachment that joined it to this VPC - a separate resource whose id appears nowhere here
  # (rules.md D-1). EC2 rejects a route to a detached gateway with InvalidGatewayID.NotAttached, and
  # because it is a race between two independent resources it fails on some applies and not others.
  depends_on = [aws_internet_gateway_attachment.egress_igw_attachment]
}
resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}
resource "aws_eip" "nat_gateway" {
  for_each = local.public_subnets

  # domain = "vpc" explicitly, where the _monolithic file's aws_eip blocks were empty. The provider
  # defaults to a VPC address, so this is documentation rather than a behaviour change - but it is the
  # address the internet sees as the source of everything this project sends, which is worth naming.
  domain = "vpc"
  tags = {
    Name = "${var.name}-natgw-${each.key}"
  }
}
# A NAT gateway per zone, as the _monolithic template had. Two gateways rather than one because the
# attachment subnets route to the gateway in their own zone: a shared gateway would send half the
# traffic across a zone boundary and would take both zones down with its own.
resource "aws_nat_gateway" "nat_gateway" {
  for_each = local.public_subnets

  allocation_id = aws_eip.nat_gateway[each.key].allocation_id
  subnet_id     = aws_subnet.public[each.key].id
  tags = {
    Name = "${var.name}-natgw-${each.key}"
  }

  # A NAT gateway created before its VPC has an internet gateway comes up in a failed state, and the
  # state is terminal - it does not recover when the gateway appears later. Nothing in the arguments
  # above mentions either the gateway or its attachment (rules.md D-1).
  depends_on = [aws_internet_gateway_attachment.egress_igw_attachment]
}
# A route table per zone for the attachment subnets. The _monolithic template had the same shape -
# two tables, egress-priv-rt-a and egress-priv-rt-b, each with one subnet - and the reason is the
# route below: it names a specific zone's NAT gateway, so the table cannot be shared.
resource "aws_route_table" "attachment" {
  for_each = local.attachment_subnets

  vpc_id = aws_vpc.egress_vpc.id
  tags = {
    Name = "${var.name}-tgw-attach-rt-${each.key}"
  }
}
# Routes 2 and 3 of 6, one per zone. This pair is what makes this an egress VPC.
#
# What uses it: traffic from the app VPC, which arrives on the transit gateway attachment's ENI in
# this subnet. The attachment delivers the packet into the subnet; the subnet's route table decides
# where it goes next, and this sends it to the NAT gateway in the same zone.
#
# Missing: the packet arrives and is dropped, because the only other entry in this table is the VPC's
# local route and the destination is not local. The app VPC's instance sees a timeout. The transit
# gateway reports the attachment as available and its route as active, so every status check in the
# project looks correct.
resource "aws_route" "attachment_internet" {
  for_each = local.attachment_subnets

  route_table_id         = aws_route_table.attachment[each.key].id
  destination_cidr_block = var.default_route_cidr_block
  nat_gateway_id         = aws_nat_gateway.nat_gateway[each.key].id
}
resource "aws_route_table_association" "attachment" {
  for_each = aws_subnet.attachment

  subnet_id      = each.value.id
  route_table_id = aws_route_table.attachment[each.key].id
}
# The firewall subnets get no aws_route_table_association, exactly as in the _monolithic template.
# That leaves them on the VPC's main route table, which holds only the local route.
#
# This is reproduced rather than fixed, and it is the reason the firewall in this project inspects
# nothing. The full explanation, including the routes that would put it in the data path, is the long
# note above aws_networkfirewall_firewall in modules/network_firewall/main.tf - kept in one place so
# the two halves of the finding cannot drift apart.
