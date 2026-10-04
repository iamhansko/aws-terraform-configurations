# The group every machine in the cluster carries. Its job is one rule: members of
# this group can reach each other on any port.
#
# That is deliberately broad, and it is the right shape for a kubeadm cluster -
# the API server on 6443, etcd on 2379-2380, the kubelet on 10250, Calico's VXLAN
# on 4789 and BGP on 179, plus every NodePort. Enumerating them is a long list that
# changes with the CNI, and getting one wrong produces a cluster that half works.
resource "aws_security_group" "cluster" {
  name        = var.name
  description = var.description
  vpc_id      = var.vpc_id
  # The controllers and kubelets in this cluster do not add rules here, unlike an
  # EKS cluster's group, but this is still true and worth setting: it makes destroy
  # revoke whatever is attached before deleting the group, including rules something
  # outside Terraform added (rules.md F-2).
  revoke_rules_on_delete = var.revoke_rules_on_delete
  tags = {
    Name = var.name
  }
}
# Standalone rule resources, not inline ingress/egress blocks (rules.md F-2).
#
# The egress rule below matters more than it looks. An inline-block-free
# aws_security_group is created with no egress at all - Terraform revokes the
# allow-all rule AWS adds - and the _monolithic template declared this group with no
# egress block, so every instance in it lost outbound access. That breaks the build
# at the first line of user data: `dnf update` cannot reach a repository, so
# containerd, kubeadm and kubelet are never installed and nothing that follows runs.
# CloudFormation leaves the default egress rule in place, which is why the original
# template worked and its machine translation did not.
resource "aws_vpc_security_group_ingress_rule" "cluster_self" {
  security_group_id            = aws_security_group.cluster.id
  description                  = "All traffic between members of this group"
  ip_protocol                  = "-1"
  referenced_security_group_id = aws_security_group.cluster.id
}
resource "aws_vpc_security_group_egress_rule" "cluster_egress" {
  security_group_id = aws_security_group.cluster.id
  description       = "All outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
# Extra sources, keyed by a caller-chosen label rather than iterated as a list,
# because these IDs are usually another module's output and unknown at plan time -
# and an unknown value cannot be a for_each key (rules.md B-8).
resource "aws_vpc_security_group_ingress_rule" "cluster_source_group" {
  for_each                     = var.ingress_source_security_groups
  security_group_id            = aws_security_group.cluster.id
  description                  = "All traffic from the ${each.key} security group"
  ip_protocol                  = "-1"
  referenced_security_group_id = each.value
}
