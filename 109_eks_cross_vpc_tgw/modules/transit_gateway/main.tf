# The transit gateway, its route table, and one attachment per VPC.
#
# One module for all of it rather than one per attachment: an attachment is not independently
# useful, and the set of them is a single decision - which VPCs are on this gateway. That is the
# opposite call from EKS addons, which get a module each because their versions and ordering move
# independently (rules.md C-4).
resource "aws_ec2_transit_gateway" "transit_gateway" {
  description = var.description
  # Both default behaviours off, as the _monolithic template had them, and it matters: with
  # default association and propagation on, every attachment lands in the default route table and
  # learns every other attachment's routes automatically. That is convenient and it is also how a
  # VPC ends up reachable from somewhere nobody intended. Off means each association and each
  # route below is written down.
  default_route_table_association = "disable"
  default_route_table_propagation = "disable"
  auto_accept_shared_attachments  = var.auto_accept_shared_attachments
  dns_support                     = "enable"
  vpn_ecmp_support                = "enable"
  tags = {
    Name = var.name
  }
}

resource "aws_ec2_transit_gateway_route_table" "transit_gateway_route_table" {
  transit_gateway_id = aws_ec2_transit_gateway.transit_gateway.id
  tags = {
    Name = "${var.name}-rt"
  }
}

# for_each over a map the caller keys by a label, not over the subnet IDs themselves: those come
# from another module and are unknown at plan time, so they cannot be for_each keys
# (rules.md B-8).
resource "aws_ec2_transit_gateway_vpc_attachment" "attachment" {
  for_each = var.attachments

  transit_gateway_id = aws_ec2_transit_gateway.transit_gateway.id
  vpc_id             = each.value.vpc_id
  subnet_ids         = each.value.subnet_ids
  # Both off, matching the gateway's defaults. Leaving them on here would put the attachment in
  # the default route table anyway, which is what the gateway settings above went out of their way
  # to avoid.
  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false
  dns_support                                     = "enable"
  tags = {
    Name = "${var.name}-${each.key}"
  }
}

resource "aws_ec2_transit_gateway_route_table_association" "attachment" {
  for_each = aws_ec2_transit_gateway_vpc_attachment.attachment

  transit_gateway_attachment_id  = each.value.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.transit_gateway_route_table.id
}

# One route per attachment, sending that VPC's CIDR to that VPC's attachment. With propagation
# disabled these are the only routes the table has, so a missing one is a destination that
# blackholes - which produces a timeout rather than an error.
resource "aws_ec2_transit_gateway_route" "attachment" {
  for_each = var.attachments

  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.transit_gateway_route_table.id
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.attachment[each.key].id
  destination_cidr_block         = each.value.cidr_block

  # The association has to exist before a route is written into the table for that attachment.
  # Nothing in the argument values says so (rules.md D-1).
  depends_on = [aws_ec2_transit_gateway_route_table_association.attachment]
}
