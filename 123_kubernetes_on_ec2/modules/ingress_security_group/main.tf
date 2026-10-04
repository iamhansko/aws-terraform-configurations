# The group that admits public traffic to the ingress controller.
#
# There is no load balancer in this project. Traefik runs as a DaemonSet with
# hostPort 80 and 443 on one node, and an Elastic IP is attached to that node, so
# the listener is the node's own network interface - which makes this group the only
# thing between the internet and the ingress controller.
resource "aws_security_group" "ingress_security_group" {
  name        = var.name
  description = var.description
  vpc_id      = var.vpc_id
  # Nothing outside Terraform adds rules to this group here, unlike the load
  # balancer projects. It is still set: destroy revokes whatever is attached before
  # deleting the group, which is cheap insurance against a rule added by hand
  # blocking the delete (rules.md F-2).
  revoke_rules_on_delete = var.revoke_rules_on_delete
  tags = {
    Name = var.name
  }
}
# Standalone rule resources rather than inline ingress/egress blocks
# (rules.md F-2). One rule per port, and the keys come from var.ports - the same map
# the caller uses for the Traefik chart's hostPorts, so the group cannot open a port
# the controller does not listen on or miss one it does (rules.md B-5).
resource "aws_vpc_security_group_ingress_rule" "ingress_anywhere" {
  for_each          = var.allow_inbound_from_anywhere ? var.ports : {}
  security_group_id = aws_security_group.ingress_security_group.id
  description       = "Ingress port ${each.key} from anywhere"
  ip_protocol       = "tcp"
  from_port         = each.value
  to_port           = each.value
  cidr_ipv4         = "0.0.0.0/0"
}
# A rule per (port, CIDR) pair. setproduct over the port labels rather than the port
# numbers, so the resource address reads http-10.0.0.0/16 and stays stable when a
# port number changes.
resource "aws_vpc_security_group_ingress_rule" "ingress_cidr" {
  for_each = {
    for pair in setproduct(keys(var.ports), var.ingress_cidr_blocks) :
    "${pair[0]}-${pair[1]}" => { label = pair[0], port = var.ports[pair[0]], cidr = pair[1] }
  }
  security_group_id = aws_security_group.ingress_security_group.id
  description       = "Ingress port ${each.value.label} from an explicitly allowed CIDR block"
  ip_protocol       = "tcp"
  from_port         = each.value.port
  to_port           = each.value.port
  cidr_ipv4         = each.value.cidr
}
# A rule per (port, source group) pair. Built from keys() of both maps, never from
# the IDs themselves: those come from another module's security group and are
# unknown until apply, while for_each needs keys it can determine during plan. The
# caller's labels supply them (rules.md B-8).
resource "aws_vpc_security_group_ingress_rule" "ingress_source_group" {
  for_each = {
    for pair in setproduct(keys(var.ports), keys(var.ingress_source_security_groups)) :
    "${pair[0]}-${pair[1]}" => {
      label           = pair[0]
      port            = var.ports[pair[0]]
      source_label    = pair[1]
      source_group_id = var.ingress_source_security_groups[pair[1]]
    }
  }
  security_group_id            = aws_security_group.ingress_security_group.id
  description                  = "Ingress port ${each.value.label} from the ${each.value.source_label} security group"
  ip_protocol                  = "tcp"
  from_port                    = each.value.port
  to_port                      = each.value.port
  referenced_security_group_id = each.value.source_group_id
}
resource "aws_vpc_security_group_egress_rule" "ingress_egress" {
  security_group_id = aws_security_group.ingress_security_group.id
  description       = "All outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
