data "aws_region" "current" {}
locals {
  # Two zones, named rather than generated.
  #
  # The zone count follows what the project runs (rules.md C-3): two internet-facing ALBs, which AWS refuses
  # to create with fewer than two zones, and an EFS file system whose mount target has to be in the zone of
  # whichever managed instance a task lands on. Two is the smallest count at which both hold, and it is what
  # the _monolithic template's resources used. Its AzMapping also defined zone b, which nothing referenced.
  zones = {
    (var.availability_zone_suffixes[0]) = "${data.aws_region.current.region}${var.availability_zone_suffixes[0]}"
    (var.availability_zone_suffixes[1]) = "${data.aws_region.current.region}${var.availability_zone_suffixes[1]}"
  }
  # Carves the VPC CIDR into /24s regardless of the VPC prefix length.
  subnet_newbits = 24 - tonumber(split("/", var.vpc_cidr_block)[1])
  # The indices reproduce the exact addresses the _monolithic template's AzMapping assigned:
  #
  #   zone a  public 10.0.0.0/24   private 10.0.1.0/24
  #   zone b  public 10.0.2.0/24   private 10.0.3.0/24   <- defined in the mapping, never used
  #   zone c  public 10.0.4.0/24   private 10.0.5.0/24
  public_cidr_blocks = {
    (var.availability_zone_suffixes[0]) = cidrsubnet(var.vpc_cidr_block, local.subnet_newbits, 0)
    (var.availability_zone_suffixes[1]) = cidrsubnet(var.vpc_cidr_block, local.subnet_newbits, 4)
  }
  private_cidr_blocks = {
    (var.availability_zone_suffixes[0]) = cidrsubnet(var.vpc_cidr_block, local.subnet_newbits, 1)
    (var.availability_zone_suffixes[1]) = cidrsubnet(var.vpc_cidr_block, local.subnet_newbits, 5)
  }
}
resource "aws_vpc" "vpc" {
  cidr_block           = var.vpc_cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = var.vpc_name
  }
}
resource "aws_internet_gateway" "internet_gateway" {
  tags = {
    Name = var.internet_gateway_name
  }
}
# A separate attachment resource, as the conversion rendered CloudFormation's VPCGatewayAttachment. The
# gateway above deliberately carries no vpc_id - the two spellings conflict.
resource "aws_internet_gateway_attachment" "vpc_internet_gateway_attachment" {
  internet_gateway_id = aws_internet_gateway.internet_gateway.id
  vpc_id              = aws_vpc.vpc.id
}
# --- Public subnets: the two ALBs and the NAT gateways ----------------------------------------------------
#
# for_each over the zone letters. The keys are variables, known at plan, so they are safe resource addresses
# even though everything they create is not (rules.md B-8).
resource "aws_subnet" "public" {
  for_each                = local.zones
  vpc_id                  = aws_vpc.vpc.id
  availability_zone       = each.value
  cidr_block              = local.public_cidr_blocks[each.key]
  map_public_ip_on_launch = true
  tags = {
    Name = "${var.public_subnet_name}-${each.key}"
  }
}
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = var.public_route_table_name
  }
}
resource "aws_route" "public_internet" {
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.internet_gateway.id
  route_table_id         = aws_route_table.public.id
  # gateway_id references the gateway, not the attachment, and a route to an unattached gateway is rejected
  # (rules.md D-1).
  depends_on = [aws_internet_gateway_attachment.vpc_internet_gateway_attachment]
}
resource "aws_route_table_association" "public" {
  for_each       = aws_subnet.public
  route_table_id = aws_route_table.public.id
  subnet_id      = each.value.id
}
# --- Private subnets: the managed instances, the tasks and the EFS mount targets -------------------------
resource "aws_subnet" "private" {
  for_each          = local.zones
  vpc_id            = aws_vpc.vpc.id
  availability_zone = each.value
  cidr_block        = local.private_cidr_blocks[each.key]
  tags = {
    Name = "${var.private_subnet_name}-${each.key}"
  }
}
# One zonal NAT gateway and one private route table per zone, as the _monolithic template had them.
#
# The alternative is one regional NAT gateway, which other projects here use. This one keeps the original's
# shape, which has a property worth having for a service that pulls its images at every task start: each
# zone's egress is independent, so losing one gateway takes out the tasks in its zone and not the other's.
resource "aws_eip" "nat" {
  for_each = local.zones
  tags = {
    Name = "${var.nat_gateway_name}-${each.key}"
  }
}
resource "aws_nat_gateway" "nat" {
  for_each      = local.zones
  allocation_id = aws_eip.nat[each.key].allocation_id
  subnet_id     = aws_subnet.public[each.key].id
  tags = {
    Name = "${var.nat_gateway_name}-${each.key}"
  }
  # A NAT gateway is created successfully in a subnet with no route to the internet gateway, and then
  # carries no traffic. Nothing here references the attachment (rules.md D-1).
  depends_on = [aws_internet_gateway_attachment.vpc_internet_gateway_attachment]
}
resource "aws_route_table" "private" {
  for_each = local.zones
  vpc_id   = aws_vpc.vpc.id
  tags = {
    Name = "${var.private_route_table_name}-${each.key}"
  }
}
resource "aws_route" "private_nat" {
  for_each               = local.zones
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat[each.key].id
  route_table_id         = aws_route_table.private[each.key].id
}
resource "aws_route_table_association" "private" {
  for_each       = local.zones
  route_table_id = aws_route_table.private[each.key].id
  subnet_id      = aws_subnet.private[each.key].id
}
