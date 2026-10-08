locals {
  # Four subnet tiers per zone, and the split between them is the whole point of this project.
  #
  #   public   Primary CIDR, routable across the transit gateway, holds the workbench, the ALB
  #            and the public NAT gateway.
  #   private  Primary CIDR, routable. Holds the private NAT gateway and the transit gateway
  #            attachment - the attachment has to be in a routable subnet, because the other VPC
  #            has to be able to address it.
  #   cluster  Secondary CIDR (100.64/16), non-routable. The EKS control plane's cross-account
  #            ENIs go here: they only ever talk to things inside the VPC.
  #   node     Secondary CIDR, non-routable. The nodes and every pod address come out of here,
  #            which is the reason the secondary CIDR exists at all - it is what stops a cluster
  #            from exhausting a routable /16 with pod addresses.
  #
  # Traffic from a node to the other VPC is source-NATed by the private NAT gateway into the
  # routable primary CIDR on the way out, which is what makes a non-routable pod address usable
  # across the transit gateway at all.
  public_subnets = {
    for suffix in var.availability_zone_suffixes : suffix => {
      availability_zone = "${var.region}${suffix}"
      cidr_block        = var.public_subnet_cidr_blocks[suffix]
    }
  }
  private_subnets = {
    for suffix in var.availability_zone_suffixes : suffix => {
      availability_zone = "${var.region}${suffix}"
      cidr_block        = var.private_subnet_cidr_blocks[suffix]
    }
  }
  cluster_subnets = {
    for suffix in var.availability_zone_suffixes : suffix => {
      availability_zone = "${var.region}${suffix}"
      cidr_block        = var.cluster_subnet_cidr_blocks[suffix]
    }
  }
  node_subnets = {
    for suffix in var.availability_zone_suffixes : suffix => {
      availability_zone = "${var.region}${suffix}"
      cidr_block        = var.node_subnet_cidr_blocks[suffix]
    }
  }
}

resource "aws_vpc" "vpc" {
  cidr_block           = var.vpc_cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = var.name
  }
}

# The non-routable range, attached as a secondary CIDR rather than being part of the primary
# block. Both VPCs use the same 100.64/16, which is exactly why it must not be routed: the two
# would collide across the transit gateway.
resource "aws_vpc_ipv4_cidr_block_association" "secondary" {
  vpc_id     = aws_vpc.vpc.id
  cidr_block = var.secondary_cidr_block
}

# vpc_id on the gateway itself, rather than the separate aws_internet_gateway_attachment the
# conversion produced. CloudFormation models the gateway and its attachment as two resources;
# Terraform's provider takes vpc_id here, which also removes the depends_on the original needed
# on its route.
resource "aws_internet_gateway" "internet_gateway" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = "${var.name}-igw"
  }
}

resource "aws_subnet" "public" {
  for_each = local.public_subnets

  vpc_id                  = aws_vpc.vpc.id
  availability_zone       = each.value.availability_zone
  cidr_block              = each.value.cidr_block
  map_public_ip_on_launch = true
  tags = merge(var.public_subnet_tags, {
    Name = "${var.name}-public-${each.key}"
  })
}

resource "aws_subnet" "private" {
  for_each = local.private_subnets

  vpc_id            = aws_vpc.vpc.id
  availability_zone = each.value.availability_zone
  cidr_block        = each.value.cidr_block
  tags = merge(var.private_subnet_tags, {
    Name = "${var.name}-private-${each.key}"
  })
}

# Both secondary-range tiers wait on the CIDR association. A subnet in a block the VPC does not
# hold yet fails with InvalidSubnet.Range, which says nothing about ordering.
resource "aws_subnet" "cluster" {
  for_each = local.cluster_subnets

  vpc_id            = aws_vpc.vpc.id
  availability_zone = each.value.availability_zone
  cidr_block        = each.value.cidr_block
  tags = merge(var.cluster_subnet_tags, {
    Name = "${var.name}-cluster-${each.key}"
  })

  depends_on = [aws_vpc_ipv4_cidr_block_association.secondary]
}

resource "aws_subnet" "node" {
  for_each = local.node_subnets

  vpc_id            = aws_vpc.vpc.id
  availability_zone = each.value.availability_zone
  cidr_block        = each.value.cidr_block
  tags = merge(var.node_subnet_tags, {
    Name = "${var.name}-node-${each.key}"
  })

  depends_on = [aws_vpc_ipv4_cidr_block_association.secondary]
}

# One public route table for every public subnet: they all reach the internet the same way.
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = "${var.name}-public-rt"
  }
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.internet_gateway.id
}

# The route that makes the other VPC reachable from here. One per peer CIDR, keyed by the CIDR
# itself - these are configuration values, not another module's output, so they are safe as
# for_each keys (rules.md B-7; B-8 is about the opposite case).
resource "aws_route" "public_peer" {
  for_each = toset(var.peer_cidr_blocks)

  route_table_id         = aws_route_table.public.id
  destination_cidr_block = each.value
  transit_gateway_id     = var.transit_gateway_id

  # The attachment has to exist before a route can point at the gateway through it. The gateway
  # ID alone does not say that, and the route is accepted and then blackholes (rules.md D-2).
  depends_on = [var.transit_gateway_attachment_dependency]
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  route_table_id = aws_route_table.public.id
  subnet_id      = each.value.id
}

resource "aws_eip" "public_nat_gateway" {
  for_each = local.public_subnets

  domain = "vpc"
  tags = {
    Name = "${var.name}-public-natgw-${each.key}"
  }
}

# The public NAT gateway: outbound internet for everything in the private and node tiers.
resource "aws_nat_gateway" "public" {
  for_each = local.public_subnets

  allocation_id = aws_eip.public_nat_gateway[each.key].allocation_id
  subnet_id     = aws_subnet.public[each.key].id
  tags = {
    Name = "${var.name}-public-natgw-${each.key}"
  }

  depends_on = [aws_internet_gateway.internet_gateway]
}

# The private NAT gateway, which is the piece that makes this design work.
#
# It has no Elastic IP and no route to the internet. What it does is source-NAT traffic leaving
# the non-routable node tier into an address in the routable private subnet it sits in - so a
# pod at 100.64.x.y appears to the other VPC as a 192.168.x.y address it has a route back to.
# Without it the other VPC receives packets from a 100.64 source it cannot answer, and both VPCs
# use the same 100.64 block anyway.
resource "aws_nat_gateway" "private" {
  for_each = local.private_subnets

  connectivity_type = "private"
  subnet_id         = aws_subnet.private[each.key].id
  tags = {
    Name = "${var.name}-private-natgw-${each.key}"
  }
}

# A route table per zone for the private and node tiers, because each one routes through the NAT
# gateway in its own zone - a shared table would send half the traffic across a zone boundary,
# billed per gigabyte, and would lose everything in a zone whose gateway failed.
resource "aws_route_table" "private" {
  for_each = local.private_subnets

  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = "${var.name}-private-rt-${each.key}"
  }
}

resource "aws_route" "private_internet" {
  for_each = local.private_subnets

  route_table_id         = aws_route_table.private[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.public[each.key].id
}

# Straight to the transit gateway, not through the private NAT gateway: this tier is already in
# the routable primary CIDR, so there is nothing to translate.
resource "aws_route" "private_peer" {
  for_each = {
    for pair in setproduct(keys(local.private_subnets), var.peer_cidr_blocks) :
    "${pair[0]}-${pair[1]}" => { zone = pair[0], cidr = pair[1] }
  }

  route_table_id         = aws_route_table.private[each.value.zone].id
  destination_cidr_block = each.value.cidr
  transit_gateway_id     = var.transit_gateway_id

  depends_on = [var.transit_gateway_attachment_dependency]
}

resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private

  route_table_id = aws_route_table.private[each.key].id
  subnet_id      = each.value.id
}

resource "aws_route_table" "node" {
  for_each = local.node_subnets

  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = "${var.name}-node-rt-${each.key}"
  }
}

resource "aws_route" "node_internet" {
  for_each = local.node_subnets

  route_table_id         = aws_route_table.node[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.public[each.key].id
}

# Through the private NAT gateway, not the transit gateway. This is the translation step: the
# node tier is non-routable, so its traffic has to leave with a routable source address before
# the transit gateway sees it.
resource "aws_route" "node_peer" {
  for_each = {
    for pair in setproduct(keys(local.node_subnets), var.peer_cidr_blocks) :
    "${pair[0]}-${pair[1]}" => { zone = pair[0], cidr = pair[1] }
  }

  route_table_id         = aws_route_table.node[each.value.zone].id
  destination_cidr_block = each.value.cidr
  nat_gateway_id         = aws_nat_gateway.private[each.value.zone].id
}

resource "aws_route_table_association" "node" {
  for_each = aws_subnet.node

  route_table_id = aws_route_table.node[each.key].id
  subnet_id      = each.value.id
}

# The cluster tier gets no route table of its own, so it stays on the VPC's main table and has
# no route off the VPC at all. That is deliberate and it is what the tier is for: the control
# plane's ENIs only ever talk to the nodes, which are in the same VPC.
