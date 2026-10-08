data "aws_region" "current" {}
locals {
  # Carves the VPC CIDR into /24s whatever prefix length the VPC was given, so a
  # 10.1.0.0/16 VPC still yields 10.1.0.0/24 for the first subnet. Index 0 is the
  # public subnet, which reproduces the 10.0.0.0/24 the _monolithic template's
  # AzMapping assigned to PublicSubnetCidr for zone a.
  subnet_newbits = 24 - tonumber(split("/", var.vpc_cidr_block)[1])
}
# One public subnet in one zone, which is what the _monolithic template actually
# built. The zone count follows what the project runs (rules.md C-3) and this one
# runs a single Windows instance that a person connects to over RDP - a second
# zone would hold nothing.
#
# The template's AzMapping also defined PrivateSubnetCidr for all three zones,
# and no aws_subnet resource referenced any of them. Those entries came across
# from the CloudFormation mapping unused, and they are deliberately not
# reproduced: a private subnet reachable from this instance would need a NAT
# gateway billed by the hour with nothing behind it.
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
# gateway above deliberately carries no vpc_id - setting both makes apply fail
# with a dangling-attachment error on one of the two.
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

  # EC2 rejects a route to a gateway that is not attached to the VPC yet, and
  # gateway_id references the gateway rather than the attachment, so the implicit
  # graph does not order these two on its own (rules.md D-1). Without this the
  # create races and fails intermittently with InvalidGatewayID.NotAttached.
  depends_on = [aws_internet_gateway_attachment.vpc_internet_gateway_attachment]
}
resource "aws_subnet" "public_subnet_a" {
  vpc_id            = aws_vpc.vpc.id
  availability_zone = "${data.aws_region.current.region}${var.availability_zone_suffix}"
  cidr_block        = cidrsubnet(var.vpc_cidr_block, local.subnet_newbits, 0)
  # The instance is reached from the internet on 3389, so it needs a public
  # address. The _monolithic template set this on the subnet and also set
  # associate_public_ip_address on the instance; both are kept, because the
  # subnet default is what a caller launching anything else here inherits.
  map_public_ip_on_launch = true
  tags = merge(var.public_subnet_tags, {
    Name = join("-", [var.public_subnet_name, var.availability_zone_suffix])
  })
}
resource "aws_route_table_association" "public_subnet_a_route_table_association" {
  route_table_id = aws_route_table.public_subnet_route_table.id
  subnet_id      = aws_subnet.public_subnet_a.id
}
