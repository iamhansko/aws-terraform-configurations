data "aws_region" "current" {}
locals {
  # Two zones, named rather than generated.
  #
  # The zone count follows what the project runs (rules.md C-3): an internet-facing ALB, which AWS refuses to
  # create with fewer than two zones, in front of a Fargate service whose availability_zone_rebalancing only
  # means something when there is more than one zone to rebalance across. Two is the smallest count at which
  # both hold, and it is what the _monolithic template's resources used.
  #
  # That template's AzMapping defined a, b and c. No resource ever referenced the b entries, so they are not
  # reproduced here.
  zone_a = "${data.aws_region.current.region}${var.availability_zone_suffixes[0]}"
  zone_c = "${data.aws_region.current.region}${var.availability_zone_suffixes[1]}"
  # Carves the VPC CIDR into /24s regardless of the VPC prefix length, so a 10.1.0.0/16 VPC still yields
  # 10.1.0.0/24 for the first public subnet.
  subnet_newbits = 24 - tonumber(split("/", var.vpc_cidr_block)[1])
  # The indices are 0, 1, 4 and 5 rather than 0, 1, 2 and 3, and the gap is deliberate: it reproduces the
  # exact addresses the _monolithic template's AzMapping assigned.
  #
  #   zone a  public 10.0.0.0/24   private 10.0.1.0/24
  #   zone b  public 10.0.2.0/24   private 10.0.3.0/24   <- defined in the mapping, never used
  #   zone c  public 10.0.4.0/24   private 10.0.5.0/24
  public_subnet_a_cidr_block  = cidrsubnet(var.vpc_cidr_block, local.subnet_newbits, 0)
  private_subnet_a_cidr_block = cidrsubnet(var.vpc_cidr_block, local.subnet_newbits, 1)
  public_subnet_c_cidr_block  = cidrsubnet(var.vpc_cidr_block, local.subnet_newbits, 4)
  private_subnet_c_cidr_block = cidrsubnet(var.vpc_cidr_block, local.subnet_newbits, 5)
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
  tags = {
    Name = var.internet_gateway_name
  }
}
# A separate attachment resource rather than vpc_id on the gateway itself, which is how the conversion
# rendered CloudFormation's AWS::EC2::VPCGatewayAttachment. Both spellings exist in the provider and they
# conflict with each other, so the gateway above deliberately carries no vpc_id.
resource "aws_internet_gateway_attachment" "vpc_internet_gateway_attachment" {
  internet_gateway_id = aws_internet_gateway.internet_gateway.id
  vpc_id              = aws_vpc.vpc.id
}
# --- Public subnets: the ALB and the VS Code instance ---------------------------------------------------
resource "aws_subnet" "public_subnet_a" {
  vpc_id                  = aws_vpc.vpc.id
  availability_zone       = local.zone_a
  cidr_block              = local.public_subnet_a_cidr_block
  map_public_ip_on_launch = true
  tags = merge(var.public_subnet_tags, {
    Name = join("-", [var.public_subnet_name, var.availability_zone_suffixes[0]])
  })
}
resource "aws_subnet" "public_subnet_c" {
  vpc_id                  = aws_vpc.vpc.id
  availability_zone       = local.zone_c
  cidr_block              = local.public_subnet_c_cidr_block
  map_public_ip_on_launch = true
  tags = merge(var.public_subnet_tags, {
    Name = join("-", [var.public_subnet_name, var.availability_zone_suffixes[1]])
  })
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
  # A route to a gateway that is not attached to the VPC yet is rejected, and gateway_id references the
  # gateway rather than the attachment, so the graph does not order these two on its own (rules.md D-1).
  depends_on = [aws_internet_gateway_attachment.vpc_internet_gateway_attachment]
}
resource "aws_route_table_association" "public_subnet_a_route_table_association" {
  route_table_id = aws_route_table.public_subnet_route_table.id
  subnet_id      = aws_subnet.public_subnet_a.id
}
resource "aws_route_table_association" "public_subnet_c_route_table_association" {
  route_table_id = aws_route_table.public_subnet_route_table.id
  subnet_id      = aws_subnet.public_subnet_c.id
}
# --- Private subnets: the Fargate tasks ------------------------------------------------------------------
resource "aws_subnet" "private_subnet_a" {
  vpc_id            = aws_vpc.vpc.id
  availability_zone = local.zone_a
  cidr_block        = local.private_subnet_a_cidr_block
  tags = merge(var.private_subnet_tags, {
    Name = join("-", [var.private_subnet_name, var.availability_zone_suffixes[0]])
  })
}
resource "aws_subnet" "private_subnet_c" {
  vpc_id            = aws_vpc.vpc.id
  availability_zone = local.zone_c
  cidr_block        = local.private_subnet_c_cidr_block
  tags = merge(var.private_subnet_tags, {
    Name = join("-", [var.private_subnet_name, var.availability_zone_suffixes[1]])
  })
}
# One elastic IP per zone, which is what a regional NAT gateway takes - see the gateway below.
resource "aws_eip" "nat_gateway_elastic_ip_a" {
  tags = {
    Name = join("-", [var.nat_gateway_name, var.availability_zone_suffixes[0]])
  }
}
resource "aws_eip" "nat_gateway_elastic_ip_c" {
  tags = {
    Name = join("-", [var.nat_gateway_name, var.availability_zone_suffixes[1]])
  }
}
# A single regional NAT gateway with an address in each zone, as the _monolithic template declared it
# (availability_mode = "regional" with one availability_zone_address block per zone).
#
# It is the tasks' only way out, and they need one: the image is pulled from Docker Hub, and the awslogs
# driver and the ECS Exec agent both talk to regional endpoints. A task that cannot reach them stops with
# CannotPullContainerError or ResourceInitializationError before the container ever starts.
resource "aws_nat_gateway" "nat_gateway" {
  vpc_id            = aws_vpc.vpc.id
  availability_mode = "regional"
  availability_zone_address {
    availability_zone = local.zone_a
    allocation_ids    = [aws_eip.nat_gateway_elastic_ip_a.allocation_id]
  }
  availability_zone_address {
    availability_zone = local.zone_c
    allocation_ids    = [aws_eip.nat_gateway_elastic_ip_c.allocation_id]
  }
  tags = {
    Name = var.nat_gateway_name
  }
  # A NAT gateway with no path to the internet gateway is created successfully and carries no traffic.
  # Nothing in this resource references the attachment, so the ordering has to be stated (rules.md D-1).
  depends_on = [aws_internet_gateway_attachment.vpc_internet_gateway_attachment]
}
resource "aws_route_table" "private_subnet_route_table" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = var.private_route_table_name
  }
}
resource "aws_route" "private_subnet_route" {
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat_gateway.id
  route_table_id         = aws_route_table.private_subnet_route_table.id
}
resource "aws_route_table_association" "private_subnet_a_route_table_association" {
  route_table_id = aws_route_table.private_subnet_route_table.id
  subnet_id      = aws_subnet.private_subnet_a.id
}
resource "aws_route_table_association" "private_subnet_c_route_table_association" {
  route_table_id = aws_route_table.private_subnet_route_table.id
  subnet_id      = aws_subnet.private_subnet_c.id
}
