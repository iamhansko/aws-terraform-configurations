# One security group shared by all six clusters and the bastion. The _monolithic
# template created it once and passed it to every cluster's vpc_config, which is what
# lets the bastion reach six API servers without six group memberships.
#
# Standalone rule resources rather than inline ingress/egress blocks: EKS adds its own
# control-plane-to-node rules to a group it is given, and an inline block is
# authoritative over the whole group - so the next apply would revoke them
# (rules.md F-2).
resource "aws_security_group" "cluster" {
  name        = var.name
  description = var.description
  vpc_id      = var.vpc_id
  # EKS and the clusters' ENIs leave rules on this group that Terraform does not
  # track, and AWS refuses to delete a group while any rule references it. This
  # revokes them first so terraform destroy is not blocked by a DependencyViolation
  # (rules.md F-2).
  revoke_rules_on_delete = var.revoke_rules_on_delete

  tags = {
    Name = var.name
  }
}
# All traffic between members of the group. This is what makes the six clusters and
# the bastion mutually reachable without naming addresses - the bastion joins the
# group, so its kubectl reaches every cluster's private endpoint.
resource "aws_vpc_security_group_ingress_rule" "self" {
  security_group_id            = aws_security_group.cluster.id
  description                  = "All traffic between members of this group"
  ip_protocol                  = "-1"
  referenced_security_group_id = aws_security_group.cluster.id
}
# Not in the _monolithic template, which left the group with no egress rule at all -
# and a security group with no egress permits nothing outbound, so nodes carrying this
# group could not have pulled an image or reached the API server. AWS adds a default
# allow-all egress rule to a group it creates through the console or CloudFormation,
# but Terraform does not, which is exactly the kind of difference that only shows up
# as nodes failing to join.
resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.cluster.id
  description       = "All outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
