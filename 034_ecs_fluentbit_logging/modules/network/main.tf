data "aws_region" "current" {}
locals {
  # Two zones, two public subnets, and nothing else - no private subnets and no NAT gateway.
  #
  # That is what the _monolithic template built and it is reproduced deliberately, but an absence is the
  # kind of thing a reader has to notice rather than read, so it is written down here (rules.md C-3 leaves
  # the zone and subnet count to the project and asks for the reason to live in a comment).
  #
  # The consequence is that the ECS container instances, and therefore the tasks on them, run with public
  # IP addresses on a subnet routed straight at the internet gateway. For this project that path is not
  # incidental, it is the demo: the container instances pull two images from ECR, and Fluent Bit inside
  # every task calls the regional CloudWatch Logs endpoint for each batch of records. Moving these
  # instances onto a private subnet without also adding a NAT gateway, or ECR, ECR-DKR, S3 and CloudWatch
  # Logs interface endpoints, leaves the log router with nowhere to ship to - and that failure appears
  # only in the router's own log rather than anywhere in ECS.
  #
  # Two zones rather than one because the Auto Scaling group spans both, so a zone short of capacity is
  # survivable. There is no load balancer here, so the usual two-zone load balancer minimum is not what
  # sets the count.
  zone_a = "${data.aws_region.current.region}${var.availability_zone_suffixes[0]}"
  zone_b = "${data.aws_region.current.region}${var.availability_zone_suffixes[1]}"
  # Carves the VPC CIDR into /24s whatever the VPC prefix length is, so a 10.101.0.0/16 VPC yields
  # 10.101.0.0/24 and 10.101.1.0/24 - the two addresses the _monolithic template's cidrsubnet call
  # produced.
  subnet_newbits             = 24 - tonumber(split("/", var.vpc_cidr_block)[1])
  public_subnet_a_cidr_block = cidrsubnet(var.vpc_cidr_block, local.subnet_newbits, 0)
  public_subnet_b_cidr_block = cidrsubnet(var.vpc_cidr_block, local.subnet_newbits, 1)
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
  vpc_id            = aws_vpc.vpc.id
  availability_zone = local.zone_a
  cidr_block        = local.public_subnet_a_cidr_block
  # Everything in this VPC sits on a public subnet, so an instance that does not get an address here has
  # no outbound path at all.
  map_public_ip_on_launch = true
  tags = {
    Name = join("-", [var.public_subnet_name, var.availability_zone_suffixes[0]])
  }
}
resource "aws_subnet" "public_subnet_b" {
  vpc_id                  = aws_vpc.vpc.id
  availability_zone       = local.zone_b
  cidr_block              = local.public_subnet_b_cidr_block
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
  # A route to a gateway that is not attached to the VPC yet is rejected, and gateway_id references the
  # gateway rather than the attachment, so the graph does not order these two on its own (rules.md D-1).
  depends_on = [aws_internet_gateway_attachment.vpc_internet_gateway_attachment]
}
resource "aws_route_table_association" "public_subnet_a_route_table_association" {
  route_table_id = aws_route_table.public_route_table.id
  subnet_id      = aws_subnet.public_subnet_a.id
}
resource "aws_route_table_association" "public_subnet_b_route_table_association" {
  route_table_id = aws_route_table.public_route_table.id
  subnet_id      = aws_subnet.public_subnet_b.id
}
