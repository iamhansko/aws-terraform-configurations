data "aws_region" "current" {}

# The endpoints are what make a private cluster possible at all. With no NAT
# gateway the private subnets have no route off the VPC, so every AWS API the
# nodes and pods use has to arrive through one of these.
#
# One module rather than one per service: they are not independently useful, they
# all share the same subnets and security groups, and the set of them is a single
# decision - "which APIs does this cluster need to reach". This is the opposite
# call from EKS addons, which do get a module each because their versions and
# ordering move independently (rules.md C-4).
#
# The interface endpoints are created with for_each over a set of literal strings,
# which is safe: the values come from configuration and are known at plan time, so
# they can be for_each keys. A list of IDs produced by another module could not be
# (rules.md B-7/B-8).
resource "aws_vpc_endpoint" "interface" {
  for_each = var.interface_services

  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${data.aws_region.current.region}.${each.key}"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = var.private_dns_enabled
  subnet_ids          = var.subnet_ids
  security_group_ids  = var.security_group_ids

  tags = {
    Name = "${var.name_prefix}-${replace(each.key, ".", "-")}-endpoint"
  }
}
# S3 is a gateway endpoint, not an interface one, so it takes route tables instead
# of subnets and needs no security group. It is here because ECR keeps image layers
# in S3: with only the two ecr endpoints, a pull fetches the manifest and then
# stalls on the layers, which reads as a slow network rather than a missing
# endpoint.
resource "aws_vpc_endpoint" "s3" {
  count = var.create_s3_gateway_endpoint ? 1 : 0

  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${data.aws_region.current.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = var.route_table_ids

  tags = {
    Name = "${var.name_prefix}-s3-endpoint"
  }
}
