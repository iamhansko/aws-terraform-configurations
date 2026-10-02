# Enhanced subnet discovery, which is what this project is for.
#
# The VPC CNI normally allocates pod addresses only from the subnet the node's own
# primary network interface is in. When a node's subnet runs dry, pods stop getting
# addresses and sit in ContainerCreating - the node has CPU and memory to spare, so
# nothing about the symptom points at the network. The classic fix is custom
# networking: a second CIDR plus an ENIConfig custom resource per zone, plus
# AWS_VPC_K8S_CNI_CUSTOM_NETWORK_CFG and a node restart.
#
# Enhanced subnet discovery replaces all of that with a tag. The CNI lists subnets in
# the VPC, keeps the ones carrying kubernetes.io/role/cni in the same Availability
# Zone as the node, and creates secondary interfaces there - preferring whichever has
# the most free addresses. No CRD, no node restart, and existing pods keep the
# addresses they already have.
#
# This module owns the three things that make that work: the extra address space, the
# tagged subnets, and the egress path out of them. It deliberately does not own the
# VPC - it is handed an ID (rules.md B-6) - so removing this module from the root
# leaves a single-CIDR VPC behind rather than a half-dismantled one.
data "aws_region" "current" {}
locals {
  # Keys are the AZ letters written in the caller's configuration, so they are known
  # during plan; only the values that follow depend on resources (rules.md B-8).
  subnet_cidr_blocks = {
    for index, suffix in var.availability_zone_suffixes :
    suffix => cidrsubnet(
      var.secondary_cidr_block,
      var.subnet_prefix_length - tonumber(split("/", var.secondary_cidr_block)[1]),
      index,
    )
  }
}
# A second CIDR on the existing VPC rather than a wider primary CIDR, because a VPC's
# primary CIDR cannot be resized after creation. This is also the reason the range is
# CG-NAT space by default: it has to be a block that is free both here and anywhere
# this VPC might later peer with (see var.secondary_cidr_block).
resource "aws_vpc_ipv4_cidr_block_association" "secondary_cidr_block" {
  vpc_id     = var.vpc_id
  cidr_block = var.secondary_cidr_block
}
resource "aws_subnet" "cni_subnet" {
  for_each = local.subnet_cidr_blocks

  vpc_id            = var.vpc_id
  availability_zone = "${data.aws_region.current.region}${each.key}"
  cidr_block        = each.value
  # Pod interfaces only. Nothing here should get a public address of its own; egress
  # goes through the zone's NAT gateway below.
  map_public_ip_on_launch = false

  # The tag is the entire interface between this module and the CNI. Merged rather
  # than replaced so the Name tag survives, and written from variables so the key
  # appears exactly once in the configuration (rules.md B-5).
  tags = merge({
    (var.discovery_tag_key) = var.discovery_tag_value
    }, {
    Name = join("-", [var.subnet_name, each.key])
  })

  # A subnet cannot be created in address space the VPC has not been given yet, and
  # nothing in the arguments above references the association - cidr_block comes from
  # a local, not from the association resource - so Terraform would otherwise be free
  # to create both at once (rules.md D-1).
  depends_on = [aws_vpc_ipv4_cidr_block_association.secondary_cidr_block]
}
# One route table per zone, pointing at that zone's NAT gateway, so a zone failure
# cannot take out egress for the other zone's pods.
#
# This is the part that is easy to leave out and impossible to diagnose from the CNI's
# behaviour. The CNI checks the tag and the Availability Zone; it does not check
# whether the subnet can reach anything. A tagged subnet with no default route is
# discovered, used, and hands out addresses normally - and every pod that lands on one
# fails to pull its image. The event says ImagePullBackOff, which reads as a registry
# or credentials problem, and the pod's address is the only clue that it is a routing
# one.
resource "aws_route_table" "cni_subnet_route_table" {
  for_each = local.subnet_cidr_blocks

  vpc_id = var.vpc_id
  tags = {
    Name = join("-", [var.route_table_name, each.key])
  }
}
resource "aws_route_table_association" "cni_subnet_route_table_association" {
  for_each = aws_subnet.cni_subnet

  route_table_id = aws_route_table.cni_subnet_route_table[each.key].id
  subnet_id      = each.value.id
}
resource "aws_route" "cni_subnet_route" {
  for_each = aws_route_table.cni_subnet_route_table

  route_table_id         = each.value.id
  destination_cidr_block = "0.0.0.0/0"
  # Keyed lookup rather than a list index, so the mapping from zone to gateway is
  # stated rather than inferred from two lists happening to be in the same order.
  nat_gateway_id = var.nat_gateway_ids[each.key]
}
