data "aws_region" "current" {}
locals {
  # Carves the VPC CIDR into /24s whatever prefix length the VPC was given, so a 10.1.0.0/16 VPC still
  # yields 10.1.0.0/24 for the first subnet. Index 0 reproduces the 10.0.0.0/24 the _monolithic template
  # wrote literally into its single aws_subnet.
  subnet_newbits = 24 - tonumber(split("/", var.vpc_cidr_block)[1])
}
# One public subnet in one zone, which is what the _monolithic template built.
#
# The zone count follows what the project runs (rules.md C-3), and what this project runs in the VPC is a
# single instance that boots, downloads a zip, PUTs its contents into S3 and is then thrown away. A second
# zone would hold nothing, and a private subnet would need a NAT gateway billed by the hour to let that
# instance reach github.com.
#
# Worth being clear that the VPC is not load-bearing for the website at all. The bucket and both Lambda
# functions are regional services with no network attachment; the only thing that needs a subnet is the
# seeder instance. The _monolithic template still built the VPC, so it is reproduced.
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
# conflict with each other, so the gateway above deliberately carries no vpc_id - setting both makes apply
# fail with a dangling-attachment error on one of the two.
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
  destination_cidr_block = var.public_route_destination_cidr_block
  gateway_id             = aws_internet_gateway.internet_gateway.id
  route_table_id         = aws_route_table.public_subnet_route_table.id

  # EC2 rejects a route to a gateway that is not attached to the VPC yet, and gateway_id references the
  # gateway rather than the attachment, so the implicit graph does not order these two on its own
  # (rules.md D-1). Without this the create races and fails intermittently with
  # InvalidGatewayID.NotAttached.
  depends_on = [aws_internet_gateway_attachment.vpc_internet_gateway_attachment]
}
resource "aws_subnet" "public_subnet_a" {
  vpc_id            = aws_vpc.vpc.id
  availability_zone = "${data.aws_region.current.region}${var.availability_zone_suffix}"
  cidr_block        = cidrsubnet(var.vpc_cidr_block, local.subnet_newbits, 0)
  # The seeder instance has to reach github.com and the S3 API over the internet gateway, so it needs a
  # public address. Set on the subnet as the _monolithic template had it, and also on the instance - the
  # subnet default is what anything else launched here inherits.
  map_public_ip_on_launch = var.map_public_ip_on_launch
  tags = {
    Name = join("-", [var.public_subnet_name, var.availability_zone_suffix])
  }
}
resource "aws_route_table_association" "public_subnet_a_route_table_association" {
  route_table_id = aws_route_table.public_subnet_route_table.id
  subnet_id      = aws_subnet.public_subnet_a.id
}
