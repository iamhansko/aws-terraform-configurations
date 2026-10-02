# The frontend security group for a load balancer the AWS Load Balancer
# Controller manages. Created here rather than left to the controller so the
# inbound rules are reviewable in the plan, and referenced from the Ingress or
# Service by ID through an annotation.
#
# Supplying a frontend group explicitly has a side effect worth knowing: the
# controller then stops managing the node-side rules unless
# alb.ingress.kubernetes.io/manage-backend-security-group-rules (or the Service
# equivalent) asks it to. No caller in this project sets that annotation, so the
# rule from the load balancer to the pods is declared in Terraform instead - see
# load_balancer_to_pods in the root configuration (rules.md G-2).
resource "aws_security_group" "load_balancer_security_group" {
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
# Standalone rule resources rather than inline ingress/egress blocks, so the
# controller can add rules of its own to this group without Terraform reverting
# them on the next apply - inline blocks are authoritative over the whole group.
# One rule per port rather than one rule, so the group covers every listener the
# load balancer ends up with. The keys come from var.ports, which the caller also
# hands to the workload's Service, so the two cannot disagree (rules.md B-5).
resource "aws_vpc_security_group_ingress_rule" "load_balancer_anywhere_ingress" {
  for_each          = var.allow_inbound_from_anywhere ? var.ports : {}
  security_group_id = aws_security_group.load_balancer_security_group.id
  description       = "Listener port ${each.key} from anywhere"
  ip_protocol       = "tcp"
  from_port         = each.value
  to_port           = each.value
  cidr_ipv4         = "0.0.0.0/0"
}
# A rule per (port, CIDR) pair. setproduct over the port labels rather than the port
# numbers, so the resource address reads http-10.0.0.0/16 and stays stable when a
# port number changes.
resource "aws_vpc_security_group_ingress_rule" "load_balancer_cidr_ingress" {
  for_each = {
    for pair in setproduct(keys(var.ports), var.ingress_cidr_blocks) :
    "${pair[0]}-${pair[1]}" => { label = pair[0], port = var.ports[pair[0]], cidr = pair[1] }
  }
  security_group_id = aws_security_group.load_balancer_security_group.id
  description       = "Listener port ${each.value.label} from an explicitly allowed CIDR block"
  ip_protocol       = "tcp"
  from_port         = each.value.port
  to_port           = each.value.port
  cidr_ipv4         = each.value.cidr
}
# A rule per (port, source group) pair. Built from keys() of both maps, never from
# the IDs themselves: those come from another module's security group and are
# unknown until apply, while for_each needs keys it can determine during plan. The
# caller's labels supply them (rules.md B-8).
resource "aws_vpc_security_group_ingress_rule" "load_balancer_source_group_ingress" {
  for_each = {
    for pair in setproduct(keys(var.ports), keys(var.ingress_source_security_groups)) :
    "${pair[0]}-${pair[1]}" => {
      label           = pair[0]
      port            = var.ports[pair[0]]
      source_label    = pair[1]
      source_group_id = var.ingress_source_security_groups[pair[1]]
    }
  }
  security_group_id            = aws_security_group.load_balancer_security_group.id
  description                  = "Listener port ${each.value.label} from the ${each.value.source_label} security group"
  ip_protocol                  = "tcp"
  from_port                    = each.value.port
  to_port                      = each.value.port
  referenced_security_group_id = each.value.source_group_id
}
resource "aws_vpc_security_group_egress_rule" "load_balancer_egress" {
  security_group_id = aws_security_group.load_balancer_security_group.id
  description       = "All outbound, so the load balancer can reach its targets"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
