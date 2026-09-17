# The frontend security group for a load balancer the AWS Load Balancer
# Controller manages. Created here rather than left to the controller so the
# inbound rules are reviewable in the plan, and referenced from the Ingress or
# Service by ID through an annotation.
#
# Pair the annotation with
# alb.ingress.kubernetes.io/manage-backend-security-group-rules (or the Service
# equivalent): once a frontend group is supplied explicitly, the controller no
# longer manages the node-side rules unless told to.
resource "aws_security_group" "load_balancer_security_group" {
  name        = var.name
  description = var.description
  vpc_id      = var.vpc_id
  # The controllers listed above add rules to this group that Terraform does not
  # track. AWS refuses to delete a group while rules referencing it remain, and
  # a controller-added rule can reference the group being deleted (or form a
  # cycle with another group), which blocks the destroy. This revokes the
  # group's attached rules first, including the ones Terraform did not create
  # (rules.md #31).
  revoke_rules_on_delete = var.revoke_rules_on_delete
  tags = {
    Name = var.name
  }
}
# Standalone rule resources rather than inline ingress/egress blocks, so the
# controller can add rules of its own to this group without Terraform reverting
# them on the next apply - inline blocks are authoritative over the whole group.
resource "aws_vpc_security_group_ingress_rule" "load_balancer_anywhere_ingress" {
  count             = var.allow_inbound_from_anywhere ? 1 : 0
  security_group_id = aws_security_group.load_balancer_security_group.id
  description       = "Listener port from anywhere"
  ip_protocol       = "tcp"
  from_port         = var.port
  to_port           = var.port
  cidr_ipv4         = "0.0.0.0/0"
}
resource "aws_vpc_security_group_ingress_rule" "load_balancer_cidr_ingress" {
  for_each          = toset(var.ingress_cidr_blocks)
  security_group_id = aws_security_group.load_balancer_security_group.id
  description       = "Listener port from an explicitly allowed CIDR block"
  ip_protocol       = "tcp"
  from_port         = var.port
  to_port           = var.port
  cidr_ipv4         = each.value
}
# Iterating the map directly, not toset() over a list of IDs: the IDs come from
# another module's security group and are unknown until apply, and for_each
# needs keys it can determine during plan. The caller's labels supply them
# (rules.md #32).
resource "aws_vpc_security_group_ingress_rule" "load_balancer_source_group_ingress" {
  for_each                     = var.ingress_source_security_groups
  security_group_id            = aws_security_group.load_balancer_security_group.id
  description                  = "Listener port from the ${each.key} security group"
  ip_protocol                  = "tcp"
  from_port                    = var.port
  to_port                      = var.port
  referenced_security_group_id = each.value
}
resource "aws_vpc_security_group_egress_rule" "load_balancer_egress" {
  security_group_id = aws_security_group.load_balancer_security_group.id
  description       = "All outbound, so the load balancer can reach its targets"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
