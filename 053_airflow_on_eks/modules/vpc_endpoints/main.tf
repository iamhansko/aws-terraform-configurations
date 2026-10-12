# The blueprint's VPC endpoints: an S3 gateway endpoint on the private route table and an interface
# endpoint for each AWS API its nodes, its add-ons and its MWAA environment call.
#
# They are not what makes this network work - the private subnets have a NAT gateway, and every one
# of these APIs is reachable through it. What they change is the path: the calls stay inside the VPC
# instead of crossing the NAT gateway, which is also where its per-gigabyte charge comes from. The
# blueprint made the MWAA environment wait for them, and the root keeps that ordering.
#
# One module rather than one per service: they are not independently useful, they all share the same
# subnets and security group, and the set of them is a single decision - "which APIs does this
# cluster reach privately". This is the opposite call from EKS addons, which do get a module each
# because their versions and ordering move independently (rules.md C-4).
#
# The interface endpoints are created with for_each over a set of literal strings, which is safe: the
# values come from configuration and are known at plan time, so they can be for_each keys. A list of
# IDs produced by another module could not be (rules.md B-7/B-8).
resource "aws_vpc_endpoint" "interface" {
  for_each = var.interface_services

  vpc_id = var.vpc_id
  # The region comes in as a variable rather than from a data source here. This module carries
  # depends_on in the root, which defers every data source inside it to apply whenever the network
  # has a change pending - and service_name forces replacement, so a deferred region would plan every
  # endpoint as replaced on any network change (rules.md D-6).
  service_name        = "com.amazonaws.${var.region}.${each.key}"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = var.private_dns_enabled
  subnet_ids          = var.subnet_ids
  security_group_ids  = concat([aws_security_group.vpc_endpoint_security_group.id], var.additional_security_group_ids)

  tags = {
    Name = "${var.name_prefix}-${replace(each.key, ".", "-")}"
  }
}
# S3 is a gateway endpoint, not an interface one, so it takes route tables instead of subnets and
# needs no security group. MWAA reads its DAGs and requirements from S3 and ECR keeps image layers
# there, so this is the endpoint that carries the most traffic of the set.
resource "aws_vpc_endpoint" "s3" {
  count = var.create_s3_gateway_endpoint ? 1 : 0

  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = var.route_table_ids

  tags = {
    Name = "${var.name_prefix}-s3"
  }
}
# The endpoints' own security group, admitting HTTPS from the VPC's CIDR as the blueprint's
# vpc_endpoints_sg did. The callers are nodes, pods (which take addresses from the private subnets
# through the VPC CNI) and MWAA's workers, so a CIDR covers all of them where a list of source
# groups would have to name each one.
#
# Standalone rule resources rather than inline ingress/egress blocks. Inline blocks are authoritative
# over the whole group, so any rule Terraform does not know about is reverted on the next apply
# (rules.md F-2). No egress rule: security groups are stateful, so the endpoints answer without one,
# and they never open a connection of their own.
resource "aws_security_group" "vpc_endpoint_security_group" {
  name        = var.security_group_name
  description = var.security_group_description
  vpc_id      = var.vpc_id
  tags = {
    Name = var.security_group_name
  }
}
# Keyed by a caller-chosen label rather than iterated as a list: these IDs are another module's
# output, unknown at plan time, and an unknown value cannot be a for_each key (rules.md B-8).
resource "aws_vpc_security_group_ingress_rule" "endpoint_source_group_ingress" {
  for_each                     = var.ingress_source_security_groups
  security_group_id            = aws_security_group.vpc_endpoint_security_group.id
  description                  = "HTTPS from the ${each.key} security group"
  ip_protocol                  = "tcp"
  from_port                    = var.endpoint_port
  to_port                      = var.endpoint_port
  referenced_security_group_id = each.value
}
resource "aws_vpc_security_group_ingress_rule" "endpoint_cidr_ingress" {
  for_each          = toset(var.ingress_cidr_blocks)
  security_group_id = aws_security_group.vpc_endpoint_security_group.id
  description       = "HTTPS from ${each.value}"
  ip_protocol       = "tcp"
  from_port         = var.endpoint_port
  to_port           = var.endpoint_port
  cidr_ipv4         = each.value
}
