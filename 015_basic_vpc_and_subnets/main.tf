data "aws_region" "current" {}
# The whole project is one module. The _monolithic template was a single file of
# twenty-odd resources with the names inlined as a CloudFormation mappings block;
# splitting the topology into a module leaves the root doing what a root does -
# naming things and exposing them - and gives the same network module shape the
# other projects in this repository already use.
#
# There is no depends_on anywhere in this root: rules.md D-3 asks every other
# module to wait for the whole network module, and here there is no other module
# to wait.
module "network" {
  source = "./modules/network"

  vpc_cidr_block       = var.vpc_cidr_block
  enable_dns_support   = var.enable_dns_support
  enable_dns_hostnames = var.enable_dns_hostnames
  # Every name derives from one prefix variable instead of being written out as a
  # literal here (rules.md B-3), so renaming the stack is a single override.
  vpc_name                 = "${var.prefix}-vpc"
  internet_gateway_name    = "${var.prefix}-igw"
  public_subnet_name       = "${var.prefix}-public"
  private_subnet_name      = "${var.prefix}-private"
  public_route_table_name  = "${var.prefix}-public-rt"
  private_route_table_name = "${var.prefix}-private-rt"
  nat_gateway_name         = "${var.prefix}-natgw"
  map_public_ip_on_launch  = var.map_public_ip_on_launch
}
