data "aws_region" "current" {}

# One public subnet is sufficient for the single workbench; this project has no private workload or HA
# component that would justify more zones or a NAT gateway.
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = var.vpc_name
  }
}

resource "aws_internet_gateway" "this" {
  tags = {
    Name = var.internet_gateway_name
  }
}

resource "aws_internet_gateway_attachment" "this" {
  internet_gateway_id = aws_internet_gateway.this.id
  vpc_id              = aws_vpc.this.id
}

resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.this.id
  availability_zone       = "${data.aws_region.current.region}${var.availability_zone_suffix}"
  cidr_block              = cidrsubnet(var.vpc_cidr_block, 24 - tonumber(split("/", var.vpc_cidr_block)[1]), 0)
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.public_subnet_name}-${var.availability_zone_suffix}"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = var.public_route_table_name
  }
}

resource "aws_route" "public_default" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id

  # The gateway ID reference does not imply that its VPC attachment is ready (rules.md D-1).
  depends_on = [aws_internet_gateway_attachment.this]
}

resource "aws_route_table_association" "public_a" {
  route_table_id = aws_route_table.public.id
  subnet_id      = aws_subnet.public_a.id
}
