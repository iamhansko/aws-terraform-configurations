data "aws_region" "current" {}
# One public subnet, as the _monolithic template had it.
#
# The zone count follows what the project runs (rules.md C-3): one instance that CloudFront reaches over its
# public DNS name. Nothing here is load balanced or needs to survive a zone, and nothing is private, so there
# is no second zone, no private subnet and no NAT gateway to pay for.
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
resource "aws_subnet" "public_subnet_a" {
  vpc_id            = aws_vpc.vpc.id
  availability_zone = "${data.aws_region.current.region}${var.availability_zone_suffix}"
  cidr_block        = cidrsubnet(var.vpc_cidr_block, 24 - tonumber(split("/", var.vpc_cidr_block)[1]), 0)
  # The instance's public DNS name is the CloudFront EC2 origin, so it needs a public address.
  map_public_ip_on_launch = true
  tags = {
    Name = var.public_subnet_name
  }
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
  # gateway_id references the gateway, not the attachment, and a route to an unattached gateway is rejected
  # (rules.md D-1). The _monolithic template had no such ordering.
  depends_on = [aws_internet_gateway_attachment.vpc_internet_gateway_attachment]
}
resource "aws_route_table_association" "public_subnet_a_route_table_association" {
  route_table_id = aws_route_table.public_subnet_route_table.id
  subnet_id      = aws_subnet.public_subnet_a.id
}
