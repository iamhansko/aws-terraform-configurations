locals {
  zone_a = "${var.region}${var.availability_zone_suffixes[0]}"
  zone_b = "${var.region}${var.availability_zone_suffixes[1]}"

  # Four /24s out of the /16, in the order the _monolithic template produced them: public a, public b,
  # private a, private b.
  #
  # The conversion rendered CloudFormation's Fn::Cidr as a 16-element list comprehension with the new
  # bit count computed from the VPC mask at every use site:
  #
  #   element([for __i in range(16) : cidrsubnet(cidr, 32 - 8 - tonumber(split("/", cidr)[1]), __i)], 2)
  #
  # which is 32 - 8 - 16 = 8 new bits for this VPC, so /24s, and twelve of the sixteen were discarded.
  # Written out here as four named values so that a reader can see which subnet is which block without
  # evaluating an expression, and so the mask is one variable rather than arithmetic repeated four times.
  public_subnet_a_cidr_block  = cidrsubnet(var.vpc_cidr_block, var.subnet_newbits, 0)
  public_subnet_b_cidr_block  = cidrsubnet(var.vpc_cidr_block, var.subnet_newbits, 1)
  private_subnet_a_cidr_block = cidrsubnet(var.vpc_cidr_block, var.subnet_newbits, 2)
  private_subnet_b_cidr_block = cidrsubnet(var.vpc_cidr_block, var.subnet_newbits, 3)
}
resource "aws_vpc" "vpc" {
  cidr_block = var.vpc_cidr_block
  # Both on. The _monolithic template set only enable_dns_hostnames, which is accepted and does nothing
  # on its own - hostnames require resolution support, and the attribute pair is what lets instances
  # resolve the ECR, ECS and S3 service endpoints the container instances and the bastion all call.
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
# rendered CloudFormation's AWS::EC2::VPCGatewayAttachment. Both spellings exist in the provider and
# they conflict with each other, so the gateway above deliberately carries no vpc_id.
resource "aws_internet_gateway_attachment" "vpc_internet_gateway_attachment" {
  internet_gateway_id = aws_internet_gateway.internet_gateway.id
  vpc_id              = aws_vpc.vpc.id
}
# --- Public subnets: the bastion builder sits here, and so do both NAT gateways ---
resource "aws_subnet" "public_subnet_a" {
  vpc_id            = aws_vpc.vpc.id
  availability_zone = local.zone_a
  cidr_block        = local.public_subnet_a_cidr_block
  tags = {
    Name = join("-", [var.public_subnet_name, var.availability_zone_suffixes[0]])
  }
}
resource "aws_subnet" "public_subnet_b" {
  vpc_id            = aws_vpc.vpc.id
  availability_zone = local.zone_b
  cidr_block        = local.public_subnet_b_cidr_block
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
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.internet_gateway.id
  route_table_id         = aws_route_table.public_subnet_route_table.id

  # A route to a gateway that is not attached to the VPC yet is rejected with
  # InvalidGatewayID.NotAttached, and gateway_id references the gateway rather than the attachment, so
  # the graph does not order these two on its own (rules.md D-1).
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
# --- Private subnets: the container instances and the task network interfaces live here ---
#
# Two zonal NAT gateways and two private route tables, one zone each, as the _monolithic template had
# it. That is a real choice rather than a transcription artefact and it is the expensive one: a zonal
# gateway lives in one subnet, so a two-zone private network built from them needs one per zone or it
# sends the other zone's egress across the zone boundary - which works, bills inter-AZ transfer on
# every byte, and takes the whole cluster's outbound access down when that one zone has a problem.
# Keeping both means an hourly charge per gateway, which is the only reason to reduce it to one.
#
# This is the entire outbound path for everything in these subnets, and it is load bearing: the ECS
# agent cannot register an instance it cannot reach ecs.<region>.amazonaws.com from, and a task cannot
# pull its image without reaching ECR and S3.
resource "aws_eip" "nat_gateway_a_elastic_ip" {
  tags = {
    Name = join("-", [var.nat_gateway_name, var.availability_zone_suffixes[0]])
  }
}
resource "aws_eip" "nat_gateway_b_elastic_ip" {
  tags = {
    Name = join("-", [var.nat_gateway_name, var.availability_zone_suffixes[1]])
  }
}
resource "aws_nat_gateway" "nat_gateway_a" {
  allocation_id = aws_eip.nat_gateway_a_elastic_ip.allocation_id
  subnet_id     = aws_subnet.public_subnet_a.id
  tags = {
    Name = join("-", [var.nat_gateway_name, var.availability_zone_suffixes[0]])
  }

  # A NAT gateway with no path to the internet gateway is created successfully and then carries no
  # traffic. Nothing in this resource references the attachment, so the ordering has to be stated
  # (rules.md D-1).
  depends_on = [aws_internet_gateway_attachment.vpc_internet_gateway_attachment]
}
resource "aws_nat_gateway" "nat_gateway_b" {
  allocation_id = aws_eip.nat_gateway_b_elastic_ip.allocation_id
  subnet_id     = aws_subnet.public_subnet_b.id
  tags = {
    Name = join("-", [var.nat_gateway_name, var.availability_zone_suffixes[1]])
  }

  depends_on = [aws_internet_gateway_attachment.vpc_internet_gateway_attachment]
}
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
resource "aws_route_table" "private_subnet_a_route_table" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = join("-", [var.private_route_table_name, var.availability_zone_suffixes[0]])
  }
}
resource "aws_route" "private_subnet_a_route" {
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat_gateway_a.id
  route_table_id         = aws_route_table.private_subnet_a_route_table.id
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
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat_gateway_b.id
  route_table_id         = aws_route_table.private_subnet_b_route_table.id
}
resource "aws_route_table_association" "private_subnet_b_route_table_association" {
  route_table_id = aws_route_table.private_subnet_b_route_table.id
  subnet_id      = aws_subnet.private_subnet_b.id
}
