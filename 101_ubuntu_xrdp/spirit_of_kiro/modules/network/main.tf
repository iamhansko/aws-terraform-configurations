data "aws_region" "current" {}
locals {
  # Carves the VPC CIDR into /24s regardless of the VPC prefix length, so a
  # 10.1.0.0/16 VPC still yields 10.1.0.0/24 for the first subnet. Index 0 is
  # the public subnet, which reproduces the 10.0.0.0/24 the _monolithic
  # template's AzMapping assigned to PublicSubnetCidr for zone a.
  subnet_newbits = 24 - tonumber(split("/", var.vpc_cidr_block)[1])
}
# One availability zone, not the two of 013_vscode_on_ec2 or the three the EKS
# projects use. The zone count follows what the project runs (rules.md C-3), and
# this project runs a single desktop instance that a person connects to over
# RDP: a second zone would hold nothing.
#
# There are no private subnets either, which is also what the _monolithic
# template built. Its AzMapping did define a PrivateSubnetCidr per zone, but no
# aws_subnet resource ever referenced those values - they were carried over from
# the CloudFormation mapping and left unused. Adding private subnets here would
# mean a NAT gateway billed by the hour with nothing behind it, so the unused
# mapping entries are deliberately not reproduced.
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
# A separate attachment resource rather than vpc_id on the gateway itself, which
# is how the conversion rendered CloudFormation's AWS::EC2::VPCGatewayAttachment.
# Both spellings exist in the provider and they conflict with each other, so the
# gateway above deliberately carries no vpc_id.
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

  # A route to a gateway that is not attached to the VPC yet is rejected, and
  # gateway_id references the gateway rather than the attachment, so the graph
  # does not order these two on its own (rules.md D-1).
  depends_on = [aws_internet_gateway_attachment.vpc_internet_gateway_attachment]
}
resource "aws_subnet" "public_subnet_a" {
  vpc_id            = aws_vpc.vpc.id
  availability_zone = "${data.aws_region.current.region}a"
  cidr_block        = cidrsubnet(var.vpc_cidr_block, local.subnet_newbits, 0)
  # The instance is reached from the internet over 3389, so it needs a public
  # address; the _monolithic template set this on the subnet and also set
  # associate_public_ip_address on the instance.
  map_public_ip_on_launch = true
  tags = merge(var.public_subnet_tags, {
    Name = join("-", [var.public_subnet_name, "a"])
  })
}
resource "aws_route_table_association" "public_subnet_a_route_table_association" {
  route_table_id = aws_route_table.public_subnet_route_table.id
  subnet_id      = aws_subnet.public_subnet_a.id
}
