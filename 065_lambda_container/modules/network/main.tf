# One VPC with one public subnet, as the _monolithic template had it.
#
# One availability zone is the project's decision rather than an oversight (rules.md C-3): the only thing
# placed in this network is the code-server workbench that builds the image. The Lambda function is not
# attached to a VPC at all - it reaches the public cat API and S3 over Lambda's own network - so there is no
# second subnet for it to need, no load balancer that would require two zones, and no NAT gateway to pay for.
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
# A separate attachment rather than vpc_id on the gateway, which is how the conversion rendered
# AWS::EC2::VPCGatewayAttachment. The two spellings conflict, so the gateway above carries no vpc_id.
resource "aws_internet_gateway_attachment" "internet_gateway" {
  internet_gateway_id = aws_internet_gateway.internet_gateway.id
  vpc_id              = aws_vpc.vpc.id
}
resource "aws_subnet" "public_subnet_a" {
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = var.public_subnet_cidr_block
  availability_zone       = "${var.region}${var.availability_zone_suffix}"
  map_public_ip_on_launch = true
  tags = {
    Name = var.public_subnet_name
  }
}
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = var.public_route_table_name
  }
}
resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.internet_gateway.id
  # gateway_id names the gateway, not the attachment, and a route to a gateway that is not yet attached to the
  # VPC is rejected (rules.md D-1).
  depends_on = [aws_internet_gateway_attachment.internet_gateway]
}
resource "aws_route_table_association" "public_subnet_a" {
  route_table_id = aws_route_table.public.id
  subnet_id      = aws_subnet.public_subnet_a.id
}
