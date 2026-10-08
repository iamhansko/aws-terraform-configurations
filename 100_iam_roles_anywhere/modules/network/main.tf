data "aws_region" "current" {}
locals {
  # Carves the VPC CIDR into /24s regardless of the VPC prefix length, so a 10.1.0.0/16 VPC still
  # yields 10.1.0.0/24 for the first subnet. Index 0 reproduces the 10.0.0.0/24 the _monolithic
  # template wrote as a literal.
  subnet_newbits = 24 - tonumber(split("/", var.vpc_cidr_block)[1])
}
# One public subnet in one availability zone, and no private subnets - which is what the
# _monolithic template built. The zone count follows what the project runs (rules.md C-3), and what
# this project runs in the VPC is a single short-lived instance that exports a certificate and is
# then terminated. A second zone would hold nothing, and a private subnet would need a NAT gateway
# billed by the hour for the same one instance.
#
# Public, not private, and that is load-bearing rather than careless. The bootstrap calls ACM, S3
# and Systems Manager, and this VPC has no NAT gateway and no interface endpoints, so a route to
# the internet gateway is the instance's only path to any of them. In a private subnet the
# instance launches, cloud-init hangs on the first API call, nothing is uploaded, and the apply
# fails some minutes later at the terminator Lambda's wait with nothing to say why.
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
# A separate attachment resource rather than vpc_id on the gateway itself, which is how the
# conversion rendered CloudFormation's AWS::EC2::VPCGatewayAttachment. Both spellings exist in the
# provider and they conflict with each other, so the gateway above deliberately carries no vpc_id.
resource "aws_internet_gateway_attachment" "vpc_internet_gateway_attachment" {
  internet_gateway_id = aws_internet_gateway.internet_gateway.id
  vpc_id              = aws_vpc.vpc.id
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

  # Not in the _monolithic template, and its absence there is a race rather than a difference of
  # opinion. EC2 rejects a route to a gateway that is not attached to the route table's VPC yet,
  # and gateway_id references the gateway, not the attachment - so the graph is free to create
  # this first. When it does, apply stops on
  #
  #   InvalidGatewayID.NotAttached: The gateway igw-... is not attached to VPC vpc-...
  #
  # which is intermittent, so the template looked correct most of the time (rules.md D-1).
  depends_on = [aws_internet_gateway_attachment.vpc_internet_gateway_attachment]
}
resource "aws_subnet" "public_subnet" {
  vpc_id            = aws_vpc.vpc.id
  availability_zone = "${data.aws_region.current.region}a"
  cidr_block        = cidrsubnet(var.vpc_cidr_block, local.subnet_newbits, 0)
  # The _monolithic template set this on the subnet and also set
  # associate_public_ip_address on the instance. Both are kept: the address is what gives the
  # instance a path out through the gateway above.
  map_public_ip_on_launch = true
  tags = {
    Name = var.public_subnet_name
  }
}
resource "aws_route_table_association" "public_subnet_route_table_association" {
  route_table_id = aws_route_table.public_subnet_route_table.id
  subnet_id      = aws_subnet.public_subnet.id
}
