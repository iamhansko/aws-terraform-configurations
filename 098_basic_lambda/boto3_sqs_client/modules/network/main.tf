data "aws_region" "current" {}
locals {
  # Carves the VPC CIDR into /24s whatever the VPC prefix length is, so a 10.102.0.0/16 VPC yields
  # 10.102.0.0/24 for the first subnet.
  #
  # The _monolithic conversion wrote this as a one-line expression that is worth reading once:
  #
  #   element([for __i in range(4) : cidrsubnet(aws_vpc.vpc.cidr_block, 32 - 8 - tonumber(split("/", ...)[1]), __i)], 0)
  #
  # It builds four subnet CIDRs and then throws three of them away, which is CloudFormation's Fn::Cidr
  # translated literally - that function returns a list and the template selected index 0. One subnet is
  # created here, so the list is gone and only index 0 remains.
  subnet_newbits = 24 - tonumber(split("/", var.vpc_cidr_block)[1])
}
# One subnet in one availability zone, which is what the _monolithic template built and what this project
# needs: two instances that talk to SQS and to each other. The zone count follows the workload rather than a
# convention (rules.md C-3), and there is nothing here whose availability depends on a second zone - the
# queue itself is regional and the Lambda function is not in the VPC at all.
#
# There is no private subnet and no NAT gateway. Both instances have public addresses because one of them
# serves code-server to a browser; putting the worker in a private subnet would mean a NAT gateway billed by
# the hour for a demo whose traffic is a few thousand SQS calls.
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

  # A route to a gateway that is not attached to the VPC yet is rejected, and gateway_id references the
  # gateway rather than the attachment, so the graph does not order these two on its own (rules.md D-1).
  depends_on = [aws_internet_gateway_attachment.vpc_internet_gateway_attachment]
}
resource "aws_subnet" "public_subnet_a" {
  vpc_id            = aws_vpc.vpc.id
  availability_zone = "${data.aws_region.current.region}${var.availability_zone_suffix}"
  cidr_block        = cidrsubnet(var.vpc_cidr_block, local.subnet_newbits, 0)
  # Both instances need a public address: one serves code-server to a browser, and both fetch packages,
  # code-server's release tarball and the CloudWatch agent over the internet during cloud-init.
  map_public_ip_on_launch = true
  tags = merge(var.public_subnet_tags, {
    Name = join("-", [var.public_subnet_name, var.availability_zone_suffix])
  })
}
resource "aws_route_table_association" "public_subnet_a_route_table_association" {
  route_table_id = aws_route_table.public_route_table.id
  subnet_id      = aws_subnet.public_subnet_a.id
}
