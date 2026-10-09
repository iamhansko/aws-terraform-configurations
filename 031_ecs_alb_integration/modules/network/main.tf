# One VPC, two public subnets, an internet gateway and one route table.
#
# There is no private tier and no NAT gateway, which is the shape of the original rather than an omission.
# Everything that needs the network here is reachable from, or reaches, the internet directly: the ALB is
# internet-facing, the workbench is a public box running code-server, and the Fargate tasks are launched
# into these same public subnets with assign_public_ip = true - which is how they pull from ECR and write to
# CloudWatch Logs without a NAT gateway. Adding a private tier would mean adding a NAT gateway, and that is
# a standing hourly charge for a demo that has nothing to put behind it.
data "aws_region" "current" {}
locals {
  # The zones, named rather than indexed.
  #
  # The _monolithic template selected them as element(data.aws_availability_zones.available.names, 0) and
  # element(..., 2) - the first and the third zone of whatever the region happens to return. That works in a
  # four-zone region like ap-northeast-2, where it resolves to a and c, and it has two problems that only
  # appear elsewhere: in a two-zone region (us-west-1, ca-central-1) index 2 does not exist and the plan
  # fails on an out-of-range index, and in any region the meaning of the pair changes with the length and
  # order of the list rather than being stated. The zone count itself is the project's decision
  # (rules.md C-3), and so is which zones - so both are written down here instead.
  zone_a = "${data.aws_region.current.region}${var.availability_zone_suffixes[0]}"
  zone_c = "${data.aws_region.current.region}${var.availability_zone_suffixes[1]}"
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
resource "aws_subnet" "public_subnet_a" {
  vpc_id                  = aws_vpc.vpc.id
  availability_zone       = local.zone_a
  cidr_block              = var.public_subnet_a_cidr_block
  map_public_ip_on_launch = true
  tags = {
    Name = join("-", [var.public_subnet_name, var.availability_zone_suffixes[0]])
  }
}
resource "aws_subnet" "public_subnet_c" {
  vpc_id                  = aws_vpc.vpc.id
  availability_zone       = local.zone_c
  cidr_block              = var.public_subnet_c_cidr_block
  map_public_ip_on_launch = true
  tags = {
    Name = join("-", [var.public_subnet_name, var.availability_zone_suffixes[1]])
  }
}
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = var.public_route_table_name
  }
}
resource "aws_route" "public_route" {
  route_table_id         = aws_route_table.public_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.internet_gateway.id
  # A route to a gateway not yet attached to the VPC is rejected, and gateway_id names the gateway rather
  # than the attachment, so the graph does not order these two on its own (rules.md D-1).
  depends_on = [aws_internet_gateway_attachment.vpc_internet_gateway_attachment]
}
resource "aws_route_table_association" "public_subnet_a_route_table_association" {
  subnet_id      = aws_subnet.public_subnet_a.id
  route_table_id = aws_route_table.public_route_table.id
}
resource "aws_route_table_association" "public_subnet_c_route_table_association" {
  subnet_id      = aws_subnet.public_subnet_c.id
  route_table_id = aws_route_table.public_route_table.id
}
