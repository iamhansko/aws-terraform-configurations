locals {
  # Carves the VPC CIDR into /24s whatever the VPC prefix length is, so a 10.0.0.0/16 VPC yields
  # 10.0.0.0/24 for the subnet. The prefix range this accepts is enforced on vpc_cidr_block.
  subnet_newbits = 24 - tonumber(split("/", var.vpc_cidr_block)[1])
}
# A network of this project's own, which the _monolithic template did not have. It took
# default_vpc_id and default_vpc_public_subnet_id as parameters and ran in the account's default VPC.
# Building the network here instead means the project no longer depends on a default VPC existing -
# many accounts have deleted it, and a region opted into later never had one - and terraform destroy
# removes everything the apply made.
#
# The cost of that is on the operator's side and is stated in the outputs: the test instances that
# launch_test_instance_commands starts land in the subnet below and are not in Terraform's state, so
# a destroy run while they still exist stops at this module with DependencyViolation on the subnet
# and on the internet gateway's detach (their public addresses are mapped through it).
#
# One public subnet in one availability zone, and no private subnet or NAT gateway. The zone count
# follows what the project runs (rules.md C-3), and what runs in this VPC is the workbench plus a
# couple of short-lived t3.micro instances the Config rule evaluates. The recorder, the rule and its
# Lambda are regional services outside the VPC, so a second zone would hold nothing that becomes more
# available, and a private subnet would need a NAT gateway billed by the hour for the same instances.
resource "aws_vpc" "vpc" {
  cidr_block = var.vpc_cidr_block
  # Both true, as they are in the default VPC the _monolithic template ran in. Not variables, because
  # false is not a working value for either: without DNS support the bootstrap cannot resolve the dnf
  # mirrors, GitHub or the SSM endpoints, and the SSM agent never registers - which also takes away
  # the only way in to find out why (rules.md B-1, on making a wrong value unrepresentable).
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "${var.name_prefix}-vpc"
  }
}
# vpc_id on the gateway itself rather than a separate aws_internet_gateway_attachment. The gateway is
# then attached before it counts as created, so the route below - which refers to the gateway - can
# never be sent ahead of the attachment and fail with InvalidGatewayID.NotAttached. The separate
# attachment resource elsewhere in this repository is how cfn2tf renders
# AWS::EC2::VPCGatewayAttachment; there is no template to mirror here.
resource "aws_internet_gateway" "internet_gateway" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = "${var.name_prefix}-igw"
  }
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
resource "aws_subnet" "public_subnet" {
  vpc_id            = aws_vpc.vpc.id
  availability_zone = "${var.region}${var.availability_zone_suffix}"
  cidr_block        = cidrsubnet(var.vpc_cidr_block, local.subnet_newbits, 0)
  # True, as on the default VPC subnets the _monolithic template launched into. The route to the
  # gateway above is the only way out of this VPC and it only carries traffic for an instance with a
  # public address. The workbench asks for one explicitly anyway; this is what the test instances get,
  # since their run-instances command in the outputs does not ask. The rule does not need them to be
  # reachable - Config records an instance whatever its network - but without this they would boot
  # with no path to anything, which is not how they behaved in the default VPC.
  map_public_ip_on_launch = true
  tags = {
    Name = "${var.name_prefix}-public-${var.availability_zone_suffix}"
  }
}
resource "aws_route_table_association" "public_subnet_route_table_association" {
  route_table_id = aws_route_table.public_route_table.id
  subnet_id      = aws_subnet.public_subnet.id
}
