# The spoke VPC, which in this project is the thing being protected: two private subnets, one route table,
# and no internet gateway at all.
#
# That last part is the point. There is no path out of this VPC except the transit gateway, and the transit
# gateway's default route sends everything into the egress VPC's attachment, where the route tables send it
# through the firewall before the NAT gateway. Give this VPC an internet gateway, or put the workbench
# instance in the egress VPC's public subnet instead, and every command in the project's outputs still
# succeeds - the curl returns an address, the page loads - while nothing is inspected and the firewall logs
# stay empty. The demo would prove nothing and say nothing about it.
#
# The subnets are private in that strict sense rather than in the usual "private subnet with a NAT gateway"
# sense: the NAT gateways are two VPCs away, on the far side of the firewall.
locals {
  # Same derivation as the egress VPC: /24s out of whatever prefix length the VPC has, reproducing the
  # 172.16.0.0/24 and 172.16.1.0/24 the _monolithic template hard-coded.
  subnet_newbits = 24 - tonumber(split("/", var.vpc_cidr_block)[1])
}
resource "aws_vpc" "app_vpc" {
  cidr_block           = var.vpc_cidr_block
  enable_dns_support   = var.enable_dns_support
  enable_dns_hostnames = var.enable_dns_hostnames
  tags = {
    Name = var.vpc_name
  }
}
# Two subnets in two zones, one per zone, which is what a transit gateway VPC attachment wants: the
# attachment takes one subnet per zone and that is what makes the gateway available in that zone. A second
# subnet in the same zone would fail the attachment create with DuplicateSubnetsInSameZone.
#
# No map_public_ip_on_launch, as the _monolithic template had them. An auto-assigned public address in a
# VPC with no internet gateway is unroutable, so it would be a value in the console that does nothing.
resource "aws_subnet" "app_private_subnet_a" {
  vpc_id            = aws_vpc.app_vpc.id
  availability_zone = var.availability_zone_a
  cidr_block        = cidrsubnet(var.vpc_cidr_block, local.subnet_newbits, 0)
  tags = {
    Name = "${var.private_subnet_name_prefix}-${substr(var.availability_zone_a, -1, 1)}"
  }
}
resource "aws_subnet" "app_private_subnet_b" {
  vpc_id            = aws_vpc.app_vpc.id
  availability_zone = var.availability_zone_b
  cidr_block        = cidrsubnet(var.vpc_cidr_block, local.subnet_newbits, 1)
  tags = {
    Name = "${var.private_subnet_name_prefix}-${substr(var.availability_zone_b, -1, 1)}"
  }
}
# The table carries no route of its own here. Its 0.0.0.0/0 route needs the transit gateway id and has to
# be ordered after this VPC's attachment, and this module knows about neither - so the root declares it
# against route_table_id (rules.md C-1).
#
# Until that route exists the subnets have only the local route, which is why an instance launched here
# before the root's routes land cannot reach the package repositories: cloud-init starts dnf within
# seconds of the launch and fails with a connection timeout, leaving an instance that is running and
# useless. That is the race the root's depends_on list on the instance module closes (rules.md D-2).
resource "aws_route_table" "app_rt" {
  vpc_id = aws_vpc.app_vpc.id
  tags = {
    Name = var.route_table_name
  }
}
resource "aws_route_table_association" "app_private_subnet_a_rt_association" {
  route_table_id = aws_route_table.app_rt.id
  subnet_id      = aws_subnet.app_private_subnet_a.id
}
resource "aws_route_table_association" "app_private_subnet_b_rt_association" {
  route_table_id = aws_route_table.app_rt.id
  subnet_id      = aws_subnet.app_private_subnet_b.id
}
