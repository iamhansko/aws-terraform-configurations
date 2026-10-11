# The VPC of the data-on-eks streaming/kafka blueprint (awslabs/data-on-eks@fe0b639, vpc.tf), built
# from plain resources rather than through terraform-aws-modules/vpc.
#
# The layout is the blueprint's, and it is worth knowing why it has three tiers rather than two:
#
#   - Public subnets (10.1.0.0/26, 10.1.0.64/26): the internet gateway route, the NAT gateway, the
#     internet-facing ALB in front of Grafana, and the workbench instance.
#   - RFC 1918 private subnets (10.1.1.0/24, 10.1.2.0/24): routable addresses for things that might
#     have to be reached from another network later. Nothing in this project uses them; they are
#     the blueprint's, and they carry the internal-elb tag so an internal load balancer could.
#   - Data plane subnets (100.64.0.0/17, 100.64.128.0/17) in a secondary CIDR: the EKS control plane
#     ENIs, every node and - because the VPC CNI gives pods addresses from the node's subnet - every
#     pod. Two /17s hold 65,532 addresses, which is the reason the secondary CIDR exists at all.
#
# Two availability zones, for every tier (rules.md C-3). The blueprint asked for three zones but
# supplied two subnets per tier, and terraform-aws-modules/vpc assigns zones with element(), which
# wraps: its four private subnets landed in a, b, c and a, so the data plane ended up in zones c and
# a while every other tier was in a and b. That split had no purpose anyone wrote down - the
# blueprint's own comment says "two subnets across two AZs" - so here the data plane shares zones a
# and b with the rest. Kafka still spreads its brokers across the two (rack awareness is on).
#
# One NAT gateway, in zone a, as the blueprint had it (single_nat_gateway). Zone b's nodes reach the
# internet across zones and lose egress if zone a does - the blueprint traded that for one hourly
# charge instead of two.
resource "aws_vpc" "vpc" {
  cidr_block = var.vpc_cidr_block
  # Both true, as terraform-aws-modules/vpc set them for the blueprint. Not variables: EKS requires
  # DNS support and hostnames for nodes to register, and the private API endpoint resolves only
  # inside a VPC that has both (rules.md B-1, on making a wrong value unrepresentable).
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "${var.name_prefix}-vpc"
  }
}
resource "aws_vpc_ipv4_cidr_block_association" "secondary" {
  vpc_id     = aws_vpc.vpc.id
  cidr_block = var.secondary_cidr_block
}
# vpc_id on the gateway itself rather than a separate aws_internet_gateway_attachment, so the gateway
# is attached before it counts as created and the route below can never be sent ahead of the
# attachment.
resource "aws_internet_gateway" "internet_gateway" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = "${var.name_prefix}-igw"
  }
}
resource "aws_subnet" "public_subnet_a" {
  vpc_id                  = aws_vpc.vpc.id
  availability_zone       = "${var.region}a"
  cidr_block              = var.public_subnet_cidr_blocks[0]
  map_public_ip_on_launch = true
  tags = merge(var.public_subnet_tags, {
    Name = "${var.name_prefix}-public-a"
  })
}
resource "aws_subnet" "public_subnet_b" {
  vpc_id                  = aws_vpc.vpc.id
  availability_zone       = "${var.region}b"
  cidr_block              = var.public_subnet_cidr_blocks[1]
  map_public_ip_on_launch = true
  tags = merge(var.public_subnet_tags, {
    Name = "${var.name_prefix}-public-b"
  })
}
resource "aws_subnet" "private_subnet_a" {
  vpc_id            = aws_vpc.vpc.id
  availability_zone = "${var.region}a"
  cidr_block        = var.private_subnet_cidr_blocks[0]
  tags = merge(var.private_subnet_tags, {
    Name = "${var.name_prefix}-private-a"
  })
}
resource "aws_subnet" "private_subnet_b" {
  vpc_id            = aws_vpc.vpc.id
  availability_zone = "${var.region}b"
  cidr_block        = var.private_subnet_cidr_blocks[1]
  tags = merge(var.private_subnet_tags, {
    Name = "${var.name_prefix}-private-b"
  })
}
# vpc_id read from the association rather than from the VPC, which is the whole point of the
# expression: it orders these subnets after the secondary CIDR exists. Referencing aws_vpc.vpc.id
# instead lets Terraform send CreateSubnet for 100.64.0.0/17 before the range belongs to the VPC,
# and it fails with InvalidSubnet.Range on a fresh apply only.
resource "aws_subnet" "data_plane_subnet_a" {
  vpc_id            = aws_vpc_ipv4_cidr_block_association.secondary.vpc_id
  availability_zone = "${var.region}a"
  cidr_block        = var.data_plane_subnet_cidr_blocks[0]
  tags = merge(var.private_subnet_tags, {
    Name = "${var.name_prefix}-data-plane-a"
  })
}
resource "aws_subnet" "data_plane_subnet_b" {
  vpc_id            = aws_vpc_ipv4_cidr_block_association.secondary.vpc_id
  availability_zone = "${var.region}b"
  cidr_block        = var.data_plane_subnet_cidr_blocks[1]
  tags = merge(var.private_subnet_tags, {
    Name = "${var.name_prefix}-data-plane-b"
  })
}
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = "${var.name_prefix}-public-rt"
  }
}
resource "aws_route" "public_internet_route" {
  route_table_id         = aws_route_table.public_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.internet_gateway.id
}
resource "aws_route_table_association" "public_subnet_a" {
  route_table_id = aws_route_table.public_route_table.id
  subnet_id      = aws_subnet.public_subnet_a.id
}
resource "aws_route_table_association" "public_subnet_b" {
  route_table_id = aws_route_table.public_route_table.id
  subnet_id      = aws_subnet.public_subnet_b.id
}
resource "aws_eip" "nat_gateway" {
  domain = "vpc"
  tags = {
    Name = "${var.name_prefix}-nat"
  }
  # An Elastic IP for a NAT gateway is only usable once the VPC has an internet gateway, and
  # nothing in the arguments says so (rules.md D-1).
  depends_on = [aws_internet_gateway.internet_gateway]
}
resource "aws_nat_gateway" "nat_gateway" {
  allocation_id = aws_eip.nat_gateway.allocation_id
  subnet_id     = aws_subnet.public_subnet_a.id
  tags = {
    Name = "${var.name_prefix}-nat"
  }
}
# One private route table for both private tiers in both zones, which is what single_nat_gateway
# produced in the blueprint.
resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = "${var.name_prefix}-private-rt"
  }
}
resource "aws_route" "private_nat_route" {
  route_table_id         = aws_route_table.private_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat_gateway.id
}
resource "aws_route_table_association" "private_subnet_a" {
  route_table_id = aws_route_table.private_route_table.id
  subnet_id      = aws_subnet.private_subnet_a.id
}
resource "aws_route_table_association" "private_subnet_b" {
  route_table_id = aws_route_table.private_route_table.id
  subnet_id      = aws_subnet.private_subnet_b.id
}
resource "aws_route_table_association" "data_plane_subnet_a" {
  route_table_id = aws_route_table.private_route_table.id
  subnet_id      = aws_subnet.data_plane_subnet_a.id
}
resource "aws_route_table_association" "data_plane_subnet_b" {
  route_table_id = aws_route_table.private_route_table.id
  subnet_id      = aws_subnet.data_plane_subnet_b.id
}
