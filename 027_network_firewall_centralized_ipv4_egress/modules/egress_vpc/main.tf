# The egress (inspection) VPC: three subnet tiers per availability zone, and the routes that chain them
# into the inspected path AWS's multi-VPC whitepaper calls "centralized IPv4 egress with Network Firewall
# and a NAT gateway".
#
# The whole project is this chain, so it is worth writing out once before reading any single route. For a
# packet leaving the spoke VPC for the internet:
#
#   spoke instance -> spoke route table (0.0.0.0/0 -> transit gateway)
#                  -> transit gateway (static 0.0.0.0/0 -> this VPC's attachment)
#                  -> attachment ENI in egress-peering-sn-<z>
#                  -> egress-peering-rt-<z>   (0.0.0.0/0 -> firewall endpoint in zone z)
#                  -> firewall endpoint, which inspects and forwards without rewriting addresses
#                  -> egress-firewall-rt-<z>  (0.0.0.0/0 -> NAT gateway in zone z)
#                  -> NAT gateway, which rewrites the source to its Elastic IP
#                  -> egress-public-rt        (0.0.0.0/0 -> internet gateway)
#                  -> internet
#
# and back:
#
#   internet -> internet gateway -> NAT gateway (un-rewrites the destination to the spoke address)
#            -> egress-public-rt (<spoke CIDR> -> transit gateway) -> transit gateway -> spoke VPC
#
# The return leg does not pass through the firewall, and that is the design rather than an omission. The
# firewall sits ahead of the NAT gateway, so it sees the real spoke source address on the way out; the
# whitepaper notes that ingress routing is unnecessary here because the return traffic is addressed to the
# NAT gateway's own Elastic IP and lands there by itself. Inserting the firewall into the return leg would
# need a <spoke CIDR> -> firewall endpoint route here *and* a <spoke CIDR> -> transit gateway route in each
# firewall subnet table, and neither exists in the _monolithic template.
#
# Zone affinity is the part that is easy to get wrong and impossible to see afterwards. Every "<z>" above
# has to be the same zone: the transit gateway, with appliance mode off, keeps a flow in the zone it
# arrived in whenever the destination attachment has a subnet there, so a packet from the spoke's zone a
# reaches egress-peering-sn-a. If egress-peering-rt-a pointed at zone b's firewall endpoint the packet
# would still be inspected and still reach the internet - it would just cross a zone boundary twice, be
# billed for it, and come back out of the wrong NAT gateway's address. Nothing reports that. The route
# resources below are therefore written out per zone rather than generated, so the pairing is visible on
# adjacent lines.
locals {
  # Carves the VPC CIDR into /24s whatever its prefix length is, so a 10.0.0.0/16 VPC yields the six
  # literal blocks the _monolithic template hard-coded - 10.0.0.0/24 through 10.0.5.0/24 - and a different
  # VPC CIDR still produces a consistent layout rather than six values that have to be edited by hand.
  #
  # The index order is the template's order, and it is load-bearing only in that it reproduces the
  # original: public a/b, then transit gateway attachment a/b, then firewall a/b.
  subnet_newbits = 24 - tonumber(split("/", var.vpc_cidr_block)[1])
}
resource "aws_vpc" "egress_vpc" {
  cidr_block           = var.vpc_cidr_block
  enable_dns_support   = var.enable_dns_support
  enable_dns_hostnames = var.enable_dns_hostnames
  tags = {
    Name = var.vpc_name
  }
}
# --- Public tier: the NAT gateways and the only route to the internet gateway ---
resource "aws_subnet" "egress_public_subnet_a" {
  vpc_id                  = aws_vpc.egress_vpc.id
  availability_zone       = var.availability_zone_a
  cidr_block              = cidrsubnet(var.vpc_cidr_block, local.subnet_newbits, 0)
  map_public_ip_on_launch = var.map_public_ip_on_launch
  tags = {
    Name = "${var.public_subnet_name_prefix}-${substr(var.availability_zone_a, -1, 1)}"
  }
}
resource "aws_subnet" "egress_public_subnet_b" {
  vpc_id                  = aws_vpc.egress_vpc.id
  availability_zone       = var.availability_zone_b
  cidr_block              = cidrsubnet(var.vpc_cidr_block, local.subnet_newbits, 1)
  map_public_ip_on_launch = var.map_public_ip_on_launch
  tags = {
    Name = "${var.public_subnet_name_prefix}-${substr(var.availability_zone_b, -1, 1)}"
  }
}
# --- Transit gateway attachment tier: where traffic from the spoke VPC arrives ---
resource "aws_subnet" "egress_peering_subnet_a" {
  vpc_id            = aws_vpc.egress_vpc.id
  availability_zone = var.availability_zone_a
  cidr_block        = cidrsubnet(var.vpc_cidr_block, local.subnet_newbits, 2)
  tags = {
    Name = "${var.peering_subnet_name_prefix}-${substr(var.availability_zone_a, -1, 1)}"
  }
}
resource "aws_subnet" "egress_peering_subnet_b" {
  vpc_id            = aws_vpc.egress_vpc.id
  availability_zone = var.availability_zone_b
  cidr_block        = cidrsubnet(var.vpc_cidr_block, local.subnet_newbits, 3)
  tags = {
    Name = "${var.peering_subnet_name_prefix}-${substr(var.availability_zone_b, -1, 1)}"
  }
}
# --- Firewall tier: one dedicated subnet per zone for a firewall endpoint ---
#
# Dedicated is a requirement, not a convention. A firewall endpoint cannot inspect traffic whose source or
# destination is inside the subnet it lives in, so anything else launched here would simply bypass the
# firewall - and the only evidence would be its absence from the flow logs.
resource "aws_subnet" "egress_firewall_subnet_a" {
  vpc_id            = aws_vpc.egress_vpc.id
  availability_zone = var.availability_zone_a
  cidr_block        = cidrsubnet(var.vpc_cidr_block, local.subnet_newbits, 4)
  tags = {
    Name = "${var.firewall_subnet_name_prefix}-${substr(var.availability_zone_a, -1, 1)}"
  }
}
resource "aws_subnet" "egress_firewall_subnet_b" {
  vpc_id            = aws_vpc.egress_vpc.id
  availability_zone = var.availability_zone_b
  cidr_block        = cidrsubnet(var.vpc_cidr_block, local.subnet_newbits, 5)
  tags = {
    Name = "${var.firewall_subnet_name_prefix}-${substr(var.availability_zone_b, -1, 1)}"
  }
}
resource "aws_internet_gateway" "egress_igw" {
  tags = {
    Name = var.internet_gateway_name
  }
}
# A separate attachment resource rather than vpc_id on the gateway itself, which is how the conversion
# rendered CloudFormation's AWS::EC2::VPCGatewayAttachment. Both spellings exist in the provider and they
# conflict with each other, so the gateway above deliberately carries no vpc_id.
resource "aws_internet_gateway_attachment" "egress_igw_attach" {
  internet_gateway_id = aws_internet_gateway.egress_igw.id
  vpc_id              = aws_vpc.egress_vpc.id
}
resource "aws_route_table" "egress_public_rt" {
  vpc_id = aws_vpc.egress_vpc.id
  tags = {
    Name = var.public_route_table_name
  }
}
# The outbound half of the NAT gateways' own egress. Without it a NAT gateway has nowhere to send the
# traffic it has just translated, and every flow dies at the last hop before the internet - with the
# firewall logs showing the packet was inspected and passed, which points attention at the wrong place.
resource "aws_route" "egress_public_route" {
  route_table_id         = aws_route_table.egress_public_rt.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.egress_igw.id

  # gateway_id references the gateway, not the attachment, so Terraform's graph orders this after an
  # internet gateway that may not be attached to the VPC yet. EC2 rejects that with
  # InvalidGatewayID.NotAttached - intermittently, because whether it happens depends on which of two
  # unordered creates finishes first (rules.md D-1).
  depends_on = [aws_internet_gateway_attachment.egress_igw_attach]
}
# The spoke return route is NOT here. It needs the transit gateway id and has to be ordered after this
# VPC's attachment, neither of which this module knows about, so the root declares it against
# public_route_table_id (rules.md C-1). Without it, inspected traffic reaches the internet and the replies
# die at the NAT gateway, which looks exactly like a firewall drop.
resource "aws_route_table_association" "egress_public_subnet_a_rt_association" {
  route_table_id = aws_route_table.egress_public_rt.id
  subnet_id      = aws_subnet.egress_public_subnet_a.id
}
resource "aws_route_table_association" "egress_public_subnet_b_rt_association" {
  route_table_id = aws_route_table.egress_public_rt.id
  subnet_id      = aws_subnet.egress_public_subnet_b.id
}
# One route table per attachment subnet, because the 0.0.0.0/0 route each one needs points at a different
# firewall endpoint - the one in its own zone. Sharing a single table here is the mistake that turns a
# two-zone deployment into a one-zone deployment with extra cross-zone charges.
#
# Their routes are declared in the root: the target is a firewall endpoint id, which only exists once the
# firewall has been created in the subnets this module owns, so a route here would close a cycle between
# this module and the firewall module (rules.md C-1).
resource "aws_route_table" "egress_peering_subnet_a_rt" {
  vpc_id = aws_vpc.egress_vpc.id
  tags = {
    Name = "${var.peering_route_table_name_prefix}-${substr(var.availability_zone_a, -1, 1)}"
  }
}
resource "aws_route_table_association" "egress_peering_subnet_a_rt_association" {
  route_table_id = aws_route_table.egress_peering_subnet_a_rt.id
  subnet_id      = aws_subnet.egress_peering_subnet_a.id
}
resource "aws_route_table" "egress_peering_subnet_b_rt" {
  vpc_id = aws_vpc.egress_vpc.id
  tags = {
    Name = "${var.peering_route_table_name_prefix}-${substr(var.availability_zone_b, -1, 1)}"
  }
}
resource "aws_route_table_association" "egress_peering_subnet_b_rt_association" {
  route_table_id = aws_route_table.egress_peering_subnet_b_rt.id
  subnet_id      = aws_subnet.egress_peering_subnet_b.id
}
# --- NAT gateways, one per zone, each in that zone's public subnet ---
#
# Two rather than one, for the reason a NAT gateway is a zonal resource: a single gateway would make one
# zone's egress depend on the other zone staying healthy, and would send half the inspected traffic across
# a zone boundary on every flow.
#
# The Elastic IPs are the project's visible result. Everything the spoke instance sends to the internet
# leaves as one of these two addresses, which is what makes "curl ifconfig.me" from that instance a
# complete end-to-end test of the chain at the top of this file.
resource "aws_eip" "egress_vpc_natgw_a_elastic_ip" {
  # domain = "vpc", which the _monolithic template left unset. The provider still defaults an unset domain
  # to "vpc", but the EC2-Classic-era default is deprecated and setting it keeps the plan explicit about
  # which address space this allocation comes from.
  domain = "vpc"
  tags = {
    Name = "${var.nat_gateway_name_prefix}-${substr(var.availability_zone_a, -1, 1)}"
  }
}
resource "aws_nat_gateway" "egress_vpc_natgw_a" {
  allocation_id = aws_eip.egress_vpc_natgw_a_elastic_ip.allocation_id
  subnet_id     = aws_subnet.egress_public_subnet_a.id
  tags = {
    Name = "${var.nat_gateway_name_prefix}-${substr(var.availability_zone_a, -1, 1)}"
  }

  # A NAT gateway in a subnet whose route table has no path to an internet gateway is created, reaches
  # Available, and translates traffic into a void. Nothing references the attachment from here -
  # subnet_id orders this after the subnet only - so the edge is declared (rules.md D-1).
  depends_on = [aws_internet_gateway_attachment.egress_igw_attach]
}
resource "aws_eip" "egress_vpc_natgw_b_elastic_ip" {
  domain = "vpc"
  tags = {
    Name = "${var.nat_gateway_name_prefix}-${substr(var.availability_zone_b, -1, 1)}"
  }
}
resource "aws_nat_gateway" "egress_vpc_natgw_b" {
  allocation_id = aws_eip.egress_vpc_natgw_b_elastic_ip.allocation_id
  subnet_id     = aws_subnet.egress_public_subnet_b.id
  tags = {
    Name = "${var.nat_gateway_name_prefix}-${substr(var.availability_zone_b, -1, 1)}"
  }

  depends_on = [aws_internet_gateway_attachment.egress_igw_attach]
}
# --- Firewall subnet route tables: inspected traffic leaves the firewall and enters the NAT gateway ---
#
# This is the one pairing both ends of which live in this module, so it is also the one place the zone
# pairing is enforced rather than merely documented: route table a names NAT gateway a on the line below
# it. The _monolithic template had the same two routes, with the second one named
# egress_private_subnet_b_route - a leftover from a template this one was copied from, since there is no
# private subnet tier in this VPC at all.
resource "aws_route_table" "egress_firewall_subnet_a_rt" {
  vpc_id = aws_vpc.egress_vpc.id
  tags = {
    Name = "${var.firewall_route_table_name_prefix}-${substr(var.availability_zone_a, -1, 1)}"
  }
}
resource "aws_route_table_association" "egress_firewall_subnet_a_rt_association" {
  route_table_id = aws_route_table.egress_firewall_subnet_a_rt.id
  subnet_id      = aws_subnet.egress_firewall_subnet_a.id
}
resource "aws_route" "egress_firewall_subnet_a_route" {
  route_table_id         = aws_route_table.egress_firewall_subnet_a_rt.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.egress_vpc_natgw_a.id
}
resource "aws_route_table" "egress_firewall_subnet_b_rt" {
  vpc_id = aws_vpc.egress_vpc.id
  tags = {
    Name = "${var.firewall_route_table_name_prefix}-${substr(var.availability_zone_b, -1, 1)}"
  }
}
resource "aws_route_table_association" "egress_firewall_subnet_b_rt_association" {
  route_table_id = aws_route_table.egress_firewall_subnet_b_rt.id
  subnet_id      = aws_subnet.egress_firewall_subnet_b.id
}
resource "aws_route" "egress_firewall_subnet_b_route" {
  route_table_id         = aws_route_table.egress_firewall_subnet_b_rt.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.egress_vpc_natgw_b.id
}
