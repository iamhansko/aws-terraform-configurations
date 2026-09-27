# The group every pod ENI joins. With custom networking the pods are on their own
# interfaces in the secondary CIDR rather than sharing the node's, so pod traffic is
# governed by this group and not by the node or cluster group - which is why rules
# that are implicit on an ordinary cluster have to be written out here.
#
# All rules are standalone resources. The _monolithic template put the webhook rule
# in an inline ingress block on this group and the DNS rules in separate
# aws_vpc_security_group_ingress_rule resources, which is the one combination
# rules.md F-2 rules out: an inline block is authoritative over the whole group, so
# each apply would delete the standalone rules and each of those would be re-added,
# producing a permanent diff and intermittently broken DNS. Everything is standalone
# here.
resource "aws_security_group" "pod_security_group" {
  name        = var.name
  description = var.description
  vpc_id      = var.vpc_id

  # The AWS Load Balancer Controller adds backend rules to this group that Terraform
  # does not track, and AWS will not delete a group while a rule still references it
  # (rules.md F-2).
  revoke_rules_on_delete = var.revoke_rules_on_delete

  tags = {
    Name = var.name
  }
}
# The API server calling an admission webhook. On an ordinary cluster the webhook
# pod shares the node's interface and the node group's rules cover this; with custom
# networking the pod is on an ENI in this group, so the path has to be opened
# explicitly. Without it the AWS Load Balancer Controller's webhook times out and
# the API server rejects every Ingress with a webhook error.
resource "aws_vpc_security_group_ingress_rule" "webhook" {
  security_group_id            = aws_security_group.pod_security_group.id
  description                  = "Admission webhook port from the cluster control plane"
  ip_protocol                  = "tcp"
  from_port                    = var.webhook_port
  to_port                      = var.webhook_port
  referenced_security_group_id = var.cluster_security_group_id
}
# DNS between pods. CoreDNS and its clients are all on ENIs in this group, so this
# is intra-group traffic - which is not allowed by default.
resource "aws_vpc_security_group_ingress_rule" "dns_tcp" {
  count = var.allow_all_self_traffic ? 0 : 1

  security_group_id            = aws_security_group.pod_security_group.id
  description                  = "DNS over TCP between pods"
  ip_protocol                  = "tcp"
  from_port                    = var.dns_port
  to_port                      = var.dns_port
  referenced_security_group_id = aws_security_group.pod_security_group.id
}
resource "aws_vpc_security_group_ingress_rule" "dns_udp" {
  count = var.allow_all_self_traffic ? 0 : 1

  security_group_id            = aws_security_group.pod_security_group.id
  description                  = "DNS over UDP between pods"
  ip_protocol                  = "udp"
  from_port                    = var.dns_port
  to_port                      = var.dns_port
  referenced_security_group_id = aws_security_group.pod_security_group.id
}
# Replaces the two DNS rules rather than joining them, so the group does not end up
# with a redundant narrower rule alongside an all-protocol one.
resource "aws_vpc_security_group_ingress_rule" "all_self" {
  count = var.allow_all_self_traffic ? 1 : 0

  security_group_id            = aws_security_group.pod_security_group.id
  description                  = "All traffic between members of this group"
  ip_protocol                  = "-1"
  referenced_security_group_id = aws_security_group.pod_security_group.id
}
# Pods need to reach the internet through their subnet's NAT route, the cluster's
# API server, and anything else outbound. A security group denies nothing outbound
# by default only if no egress rule exists at all - creating the group with none, as
# the _monolithic template did, actually leaves the default allow-all egress rule in
# place. Declaring it explicitly makes that visible in the plan rather than implied.
resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.pod_security_group.id
  description       = "All outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
