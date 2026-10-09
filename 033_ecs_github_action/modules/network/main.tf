data "aws_region" "current" {}
locals {
  # Two zones, named rather than generated, which is what the _monolithic template declared: a public and
  # a private subnet in each of "<region>a" and "<region>b".
  #
  # Two is also the smallest count this project works at (rules.md C-3). The ALB is internet-facing and
  # elbv2 refuses to create one with subnets in fewer than two zones, and the ECS service places awsvpc
  # tasks across the private pair.
  zone_a = "${data.aws_region.current.region}${var.availability_zone_suffixes[0]}"
  zone_b = "${data.aws_region.current.region}${var.availability_zone_suffixes[1]}"
  # Carves /24s out of the VPC CIDR whatever its prefix length is, so a /16 VPC yields 10.100.0.0/24 for
  # the first public subnet. The _monolithic template spelled the same arithmetic as
  # cidrsubnet(cidr, 32 - 8 - tonumber(split("/", cidr)[1]), i) over range(4).
  subnet_newbits = 24 - tonumber(split("/", var.vpc_cidr_block)[1])
  # Indices 0..3 in the order the original list comprehension produced them, so the addresses come out
  # the same: public a, public b, private a, private b.
  public_subnet_a_cidr_block  = cidrsubnet(var.vpc_cidr_block, local.subnet_newbits, 0)
  public_subnet_b_cidr_block  = cidrsubnet(var.vpc_cidr_block, local.subnet_newbits, 1)
  private_subnet_a_cidr_block = cidrsubnet(var.vpc_cidr_block, local.subnet_newbits, 2)
  private_subnet_b_cidr_block = cidrsubnet(var.vpc_cidr_block, local.subnet_newbits, 3)
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
# conflict, so the gateway above deliberately carries no vpc_id.
resource "aws_internet_gateway_attachment" "vpc_internet_gateway_attachment" {
  internet_gateway_id = aws_internet_gateway.internet_gateway.id
  vpc_id              = aws_vpc.vpc.id
}
# --- Public subnets: the ALB and the code-server workbench -------------------------------------------------
resource "aws_subnet" "public_subnet_a" {
  vpc_id                  = aws_vpc.vpc.id
  availability_zone       = local.zone_a
  cidr_block              = local.public_subnet_a_cidr_block
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
resource "aws_route_table" "public_subnet_route_table" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = var.public_route_table_name
  }
}
resource "aws_route" "public_subnet_route" {
  route_table_id         = aws_route_table.public_subnet_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.internet_gateway.id
  # A route to a gateway that is not attached to the VPC yet is rejected, and gateway_id names the gateway
  # rather than the attachment, so nothing orders these two on its own (rules.md D-1).
  depends_on = [aws_internet_gateway_attachment.vpc_internet_gateway_attachment]
}
resource "aws_route_table_association" "public_subnet_a_route_table_association" {
  route_table_id = aws_route_table.public_subnet_route_table.id
  subnet_id      = aws_subnet.public_subnet_a.id
}
resource "aws_route_table_association" "public_subnet_b_route_table_association" {
  route_table_id = aws_route_table.public_subnet_route_table.id
  subnet_id      = aws_subnet.public_subnet_b.id
}
# --- Private subnets: the ECS container instances and the awsvpc task ENIs ---------------------------------
#
# One NAT gateway and one route table per zone, as the _monolithic template had it. A zonal gateway per
# zone rather than one shared gateway means a zone losing its gateway does not take the other zone's
# outbound traffic with it; the cost is a second gateway and a second elastic IP.
resource "aws_subnet" "private_subnet_a" {
  vpc_id            = aws_vpc.vpc.id
  availability_zone = local.zone_a
  cidr_block        = local.private_subnet_a_cidr_block
  tags = {
    Name = join("-", [var.private_subnet_name, var.availability_zone_suffixes[0]])
  }
}
resource "aws_subnet" "private_subnet_b" {
  vpc_id            = aws_vpc.vpc.id
  availability_zone = local.zone_b
  cidr_block        = local.private_subnet_b_cidr_block
  tags = {
    Name = join("-", [var.private_subnet_name, var.availability_zone_suffixes[1]])
  }
}
resource "aws_eip" "nat_gateway_elastic_ip_a" {
  tags = {
    Name = join("-", [var.nat_gateway_name, var.availability_zone_suffixes[0]])
  }
}
resource "aws_eip" "nat_gateway_elastic_ip_b" {
  tags = {
    Name = join("-", [var.nat_gateway_name, var.availability_zone_suffixes[1]])
  }
}
resource "aws_nat_gateway" "nat_gateway_a" {
  allocation_id = aws_eip.nat_gateway_elastic_ip_a.allocation_id
  subnet_id     = aws_subnet.public_subnet_a.id
  tags = {
    Name = join("-", [var.nat_gateway_name, var.availability_zone_suffixes[0]])
  }
  # A NAT gateway with no path to the internet gateway is created successfully and carries no traffic.
  # Nothing here references the attachment, so the ordering has to be stated (rules.md D-1).
  depends_on = [aws_internet_gateway_attachment.vpc_internet_gateway_attachment]
}
resource "aws_nat_gateway" "nat_gateway_b" {
  allocation_id = aws_eip.nat_gateway_elastic_ip_b.allocation_id
  subnet_id     = aws_subnet.public_subnet_b.id
  tags = {
    Name = join("-", [var.nat_gateway_name, var.availability_zone_suffixes[1]])
  }
  depends_on = [aws_internet_gateway_attachment.vpc_internet_gateway_attachment]
}
resource "aws_route_table" "private_subnet_a_route_table" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = join("-", [var.private_route_table_name, var.availability_zone_suffixes[0]])
  }
}
resource "aws_route" "private_subnet_a_route" {
  route_table_id         = aws_route_table.private_subnet_a_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat_gateway_a.id
}
resource "aws_route_table_association" "private_subnet_a_route_table_association" {
  route_table_id = aws_route_table.private_subnet_a_route_table.id
  subnet_id      = aws_subnet.private_subnet_a.id
}
resource "aws_route_table" "private_subnet_b_route_table" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = join("-", [var.private_route_table_name, var.availability_zone_suffixes[1]])
  }
}
resource "aws_route" "private_subnet_b_route" {
  route_table_id         = aws_route_table.private_subnet_b_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat_gateway_b.id
}
resource "aws_route_table_association" "private_subnet_b_route_table_association" {
  route_table_id = aws_route_table.private_subnet_b_route_table.id
  subnet_id      = aws_subnet.private_subnet_b.id
}
