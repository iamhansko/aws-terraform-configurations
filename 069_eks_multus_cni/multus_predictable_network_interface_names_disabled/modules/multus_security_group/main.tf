# The security group the nodes attach their Multus ENIs with.
#
# A group of its own rather than the cluster security group, which is what the node bootstrap used
# before. Two reasons, and the second is the one that matters:
#
#   - the cluster security group is shared by the control plane's managed interfaces, the node's
#     primary interface and every pod the VPC CNI addresses, so anything opened for the secondary
#     network was opened for all of that too;
#   - a secondary interface is only a separation boundary if its rules differ from the primary's.
#     With one group for both, "management traffic and data traffic are separated" is a statement
#     about which interface a packet left on, not something the VPC enforces.
#
# Nothing here is reachable from outside the VPC: the addresses on this network are assigned by an
# IPAM that is not the VPC's, and the VPC only routes them once they are also assigned as secondary
# addresses on the ENI itself.
resource "aws_security_group" "multus_security_group" {
  name        = var.name
  description = var.description
  vpc_id      = var.vpc_id
  # Not set, deliberately, unlike the load balancer groups in this repository: no controller adds
  # rules to this group. The ENIs that use it are created by the node's own bootstrap rather than by
  # Terraform, but they carry DeleteOnTermination, and the node group depends on this module through
  # the security group ID in its user data - so destroy takes the nodes, then their ENIs, then this
  # group (rules.md F-2).
  tags = {
    Name = var.name
  }
}
# Standalone rule resources rather than inline ingress/egress blocks. Nothing else writes rules into
# this group today, but inline blocks are authoritative over the whole group, and that is a decision
# that gets reversed by one annotation elsewhere - at which point the rules someone else added
# disappear on the next apply, silently (rules.md F-2).
resource "aws_vpc_security_group_ingress_rule" "multus_self_ingress" {
  security_group_id = aws_security_group.multus_security_group.id
  description       = "All traffic between members of this group"
  ip_protocol       = "-1"
  # Self-referencing, which is what lets Multus pods on different nodes reach each other: every
  # node's Multus ENIs are in this group, so the traffic arrives from a member of it. Note that this
  # rule is necessary but not sufficient - the VPC also has to know the pod address, which it only
  # does once that address is assigned as a secondary address on the sending ENI.
  referenced_security_group_id = aws_security_group.multus_security_group.id
}
# Iterating the map directly, not toset() over a list of IDs: the IDs come from another module's
# security group and are unknown until apply, and for_each needs keys it can determine during plan.
# The caller's labels supply them (rules.md B-8).
resource "aws_vpc_security_group_ingress_rule" "multus_source_group_ingress" {
  for_each                     = var.ingress_source_security_groups
  security_group_id            = aws_security_group.multus_security_group.id
  description                  = "All traffic from the ${each.key} security group"
  ip_protocol                  = "-1"
  referenced_security_group_id = each.value
}
resource "aws_vpc_security_group_ingress_rule" "multus_cidr_ingress" {
  for_each          = toset(var.ingress_cidr_blocks)
  security_group_id = aws_security_group.multus_security_group.id
  description       = "All traffic from an explicitly allowed CIDR block"
  ip_protocol       = "-1"
  cidr_ipv4         = each.value
}
resource "aws_vpc_security_group_egress_rule" "multus_egress" {
  security_group_id = aws_security_group.multus_security_group.id
  description       = "All outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
