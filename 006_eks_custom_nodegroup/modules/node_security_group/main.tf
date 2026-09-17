# One security group attached to both the cluster's managed network interfaces
# and every worker node, so node-to-node and node-to-control-plane traffic is
# covered by the single self-referencing rule below. This mirrors the
# _monolithic template's eks-node-sg, which the cluster's vpc_config and both
# launch templates referenced.
resource "aws_security_group" "node_security_group" {
  name        = var.name
  description = var.description
  vpc_id      = var.vpc_id
  # The controllers listed above add rules to this group that Terraform does not
  # track. AWS refuses to delete a group while rules referencing it remain, and
  # a controller-added rule can reference the group being deleted (or form a
  # cycle with another group), which blocks the destroy. This revokes the
  # group's attached rules first, including the ones Terraform did not create
  # (rules.md F-2).
  revoke_rules_on_delete = var.revoke_rules_on_delete
  tags = {
    Name = var.name
  }
}
# Written as standalone rule resources rather than inline ingress/egress blocks
# so the AWS Load Balancer Controller can add its own backend rules to this
# group without Terraform reverting them on the next apply (inline blocks are
# authoritative over the whole group).
resource "aws_vpc_security_group_ingress_rule" "node_security_group_self_ingress" {
  security_group_id            = aws_security_group.node_security_group.id
  description                  = "All traffic between members of this group"
  ip_protocol                  = "-1"
  referenced_security_group_id = aws_security_group.node_security_group.id
}
# Iterating the map directly, not toset() over a list of IDs: the IDs come from
# another module's security group and are unknown until apply, and for_each needs
# keys it can determine during plan. The caller's labels supply them
# (rules.md B-8).
resource "aws_vpc_security_group_ingress_rule" "node_security_group_source_ingress" {
  for_each                     = var.ingress_source_security_groups
  security_group_id            = aws_security_group.node_security_group.id
  description                  = "All traffic from the ${each.key} security group"
  ip_protocol                  = "-1"
  referenced_security_group_id = each.value
}
resource "aws_vpc_security_group_egress_rule" "node_security_group_egress" {
  security_group_id = aws_security_group.node_security_group.id
  description       = "All outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
