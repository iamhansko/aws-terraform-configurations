# The group the ElastiCache node and the two VPC-attached Lambda functions share. Members reach each other on
# every TCP port, which is the _monolithic template's one rule.
resource "aws_security_group" "resource_security_group" {
  name        = var.name
  description = var.description
  vpc_id      = var.vpc_id
  tags = {
    Name = var.name
  }
}
resource "aws_vpc_security_group_ingress_rule" "self_ingress" {
  security_group_id            = aws_security_group.resource_security_group.id
  description                  = "All TCP between members of this group"
  ip_protocol                  = "tcp"
  from_port                    = 0
  to_port                      = 65535
  referenced_security_group_id = aws_security_group.resource_security_group.id
}
# Restores the egress CloudFormation left on this group, and it is load bearing.
#
# The _monolithic template declared this group with no inline blocks at all, which reads as if its default
# allow-all egress survives. It does not: the AWS provider revokes the default egress rule on every security
# group it creates, inline blocks or not (resourceSecurityGroupCreate calls RevokeSecurityGroupEgress
# unconditionally). The group came up with no egress, and game-rank-update and game-rank-reader live in it - a
# Lambda ENI needs an egress rule to open the connection to Redis, so both functions timed out on their first
# Redis call and the leaderboard stayed empty. The ElastiCache node itself never initiates anything and did not
# care.
resource "aws_vpc_security_group_egress_rule" "all_outbound" {
  security_group_id = aws_security_group.resource_security_group.id
  description       = "All outbound, as CloudFormation left it"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
resource "aws_vpc_security_group_ingress_rule" "source_ingress" {
  for_each                     = var.ingress_source_security_groups
  security_group_id            = aws_security_group.resource_security_group.id
  description                  = "Port ${var.ingress_source_port} from the ${each.key} security group"
  ip_protocol                  = "tcp"
  from_port                    = var.ingress_source_port
  to_port                      = var.ingress_source_port
  referenced_security_group_id = each.value
}
