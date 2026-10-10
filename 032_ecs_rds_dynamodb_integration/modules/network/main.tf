data "aws_region" "current" {}
locals {
  # Two zones, and the count is a decision rather than an inheritance.
  #
  # The _monolithic template's AzMapping defined three - a, b and c, with a CIDR pair each - and then no
  # resource ever referenced c. The c entries were dead configuration, so they are not reproduced.
  #
  # Two is also the smallest count this project can run on, which is why it is the count kept rather than
  # raised to three (rules.md C-3):
  #
  #   - an RDS DB subnet group is rejected with fewer than two Availability Zones, and multi_az on the
  #     primary instance needs a second zone to put the standby in
  #   - the container instance Auto Scaling group is asked to balance across zones
  #     (capacity_distribution_strategy), which means nothing with one
  #
  # and a third zone would add a third NAT gateway, which is the most expensive idle resource here, for
  # nothing this project demonstrates.
  #
  # The zone names are the region plus a letter rather than data.aws_availability_zones, which is what the
  # _monolithic template did and what the rest of this repository does. The reason to keep it: the list is
  # explicit, so the subnet in "zone a" is the same physical zone on every apply and in every account,
  # whereas the data source returns zone names in an order that is not guaranteed and would silently move
  # subnets between zones if that order changed. The cost is that a letter which does not exist in the
  # region - or exists but cannot offer the instance types asked for - fails at apply rather than at plan,
  # so availability_zone_suffixes is the first thing to change when running this outside ap-northeast-2.
  zone_a = "${data.aws_region.current.region}${var.availability_zone_suffixes[0]}"
  zone_b = "${data.aws_region.current.region}${var.availability_zone_suffixes[1]}"
  # Carves the VPC CIDR into /24s whatever the VPC prefix length is, so a 10.1.0.0/16 VPC still gives
  # 10.1.0.0/24 as its first public subnet. The indices reproduce the addresses the AzMapping assigned:
  #
  #   zone a  public 10.0.0.0/24   private 10.0.1.0/24
  #   zone b  public 10.0.2.0/24   private 10.0.3.0/24
  subnet_newbits              = 24 - tonumber(split("/", var.vpc_cidr_block)[1])
  public_subnet_a_cidr_block  = cidrsubnet(var.vpc_cidr_block, local.subnet_newbits, 0)
  private_subnet_a_cidr_block = cidrsubnet(var.vpc_cidr_block, local.subnet_newbits, 1)
  public_subnet_b_cidr_block  = cidrsubnet(var.vpc_cidr_block, local.subnet_newbits, 2)
  private_subnet_b_cidr_block = cidrsubnet(var.vpc_cidr_block, local.subnet_newbits, 3)
}
resource "aws_vpc" "vpc" {
  cidr_block = var.vpc_cidr_block
  # Both required here rather than merely tidy. An awsvpc task resolves the DynamoDB and Secrets Manager
  # endpoints through the Amazon-provided resolver, and ECS only gives a task an internal DNS hostname when
  # both of these are on.
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
# A separate attachment resource rather than vpc_id on the gateway, which is how AWS::EC2::VPCGatewayAttachment
# converted. Both spellings exist in the provider and conflict, so the gateway above carries no vpc_id.
resource "aws_internet_gateway_attachment" "vpc_internet_gateway_attachment" {
  internet_gateway_id = aws_internet_gateway.internet_gateway.id
  vpc_id              = aws_vpc.vpc.id
}
# --- Public subnets: the workbench and the NAT gateways ---------------------------------------------------
resource "aws_subnet" "public_subnet_a" {
  vpc_id                  = aws_vpc.vpc.id
  availability_zone       = local.zone_a
  cidr_block              = local.public_subnet_a_cidr_block
  map_public_ip_on_launch = var.map_public_ip_on_launch
  tags = merge(var.public_subnet_tags, {
    Name = "${var.public_subnet_name_prefix}${var.availability_zone_suffixes[0]}"
  })
}
resource "aws_subnet" "public_subnet_b" {
  vpc_id                  = aws_vpc.vpc.id
  availability_zone       = local.zone_b
  cidr_block              = local.public_subnet_b_cidr_block
  map_public_ip_on_launch = var.map_public_ip_on_launch
  tags = merge(var.public_subnet_tags, {
    Name = "${var.public_subnet_name_prefix}${var.availability_zone_suffixes[1]}"
  })
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
  # A route to a gateway not yet attached to the VPC is rejected, and gateway_id references the gateway
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
# --- Private subnets: the container instances, the tasks and the database ---------------------------------
resource "aws_subnet" "private_subnet_a" {
  vpc_id            = aws_vpc.vpc.id
  availability_zone = local.zone_a
  cidr_block        = local.private_subnet_a_cidr_block
  tags = merge(var.private_subnet_tags, {
    Name = "${var.private_subnet_name_prefix}${var.availability_zone_suffixes[0]}"
  })
}
resource "aws_subnet" "private_subnet_b" {
  vpc_id            = aws_vpc.vpc.id
  availability_zone = local.zone_b
  cidr_block        = local.private_subnet_b_cidr_block
  tags = merge(var.private_subnet_tags, {
    Name = "${var.private_subnet_name_prefix}${var.availability_zone_suffixes[1]}"
  })
}
# One NAT gateway per zone with its own route table, as the _monolithic template declared them. Two
# gateways rather than one shared is what keeps a zone's outbound traffic inside that zone, and it is also
# what the _monolithic template paid for, so it is reproduced.
#
# These are not optional decoration here. An awsvpc task on an EC2 container instance never gets a public
# address, so everything the tasks and the instances reach outside the VPC goes through these: the ECS
# agent registering the instance, the ECR authorization token and image layers, the DynamoDB and Secrets
# Manager endpoints, and the CloudWatch Logs endpoint the awslogs driver writes to.
resource "aws_eip" "nat_gateway_elastic_ip_a" {
  tags = {
    Name = "${var.nat_gateway_name_prefix}${var.availability_zone_suffixes[0]}"
  }
}
resource "aws_nat_gateway" "nat_gateway_a" {
  allocation_id = aws_eip.nat_gateway_elastic_ip_a.allocation_id
  subnet_id     = aws_subnet.public_subnet_a.id
  tags = {
    Name = "${var.nat_gateway_name_prefix}${var.availability_zone_suffixes[0]}"
  }
  # A NAT gateway with no path to the internet gateway is created successfully and carries no traffic.
  # Nothing here references the attachment, so the ordering has to be stated (rules.md D-1).
  depends_on = [aws_internet_gateway_attachment.vpc_internet_gateway_attachment]
}
resource "aws_route_table" "private_subnet_a_route_table" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = "${var.private_route_table_name_prefix}${var.availability_zone_suffixes[0]}"
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
resource "aws_eip" "nat_gateway_elastic_ip_b" {
  tags = {
    Name = "${var.nat_gateway_name_prefix}${var.availability_zone_suffixes[1]}"
  }
}
resource "aws_nat_gateway" "nat_gateway_b" {
  allocation_id = aws_eip.nat_gateway_elastic_ip_b.allocation_id
  subnet_id     = aws_subnet.public_subnet_b.id
  tags = {
    Name = "${var.nat_gateway_name_prefix}${var.availability_zone_suffixes[1]}"
  }
  depends_on = [aws_internet_gateway_attachment.vpc_internet_gateway_attachment]
}
resource "aws_route_table" "private_subnet_b_route_table" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = "${var.private_route_table_name_prefix}${var.availability_zone_suffixes[1]}"
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
