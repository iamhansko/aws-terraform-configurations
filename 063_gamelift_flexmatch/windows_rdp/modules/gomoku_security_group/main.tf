# GomokuDefault: the group the ElastiCache node and the two VPC-attached Lambda
# functions (game-rank-update, game-rank-reader) share, so that membership is the
# whole access rule - anything in the group reaches anything else in it on any
# TCP port, which is how the functions reach Redis on 6379.
resource "aws_security_group" "gomoku_default" {
  name        = var.name
  description = var.description
  vpc_id      = var.vpc_id
  tags = {
    Name = var.name
  }
}
resource "aws_vpc_security_group_ingress_rule" "self_tcp" {
  security_group_id            = aws_security_group.gomoku_default.id
  description                  = "All TCP between members of this group"
  ip_protocol                  = "tcp"
  from_port                    = 0
  to_port                      = 65535
  referenced_security_group_id = aws_security_group.gomoku_default.id
}
# The egress rule the _monolithic template did not have, and needed.
#
# In CloudFormation this group kept EC2's default allow-all egress, because the
# template named no SecurityGroupEgress. It does not survive the conversion, and
# not for the reason inline blocks are usually blamed for: this group has no
# inline blocks at all. aws_security_group revokes the default 0.0.0.0/0 (and
# ::/0) egress rule unconditionally right after CreateSecurityGroup in any VPC -
# the provider's own NOTE on egress rules says so, and
# internal/service/ec2/vpc_security_group.go does it before reading any
# configuration. So the converted group had no egress whatsoever.
#
# Security groups are stateful, which makes that one-sided: the ingress rule
# above lets a member accept a connection, but the member opening it needs an
# egress rule too. Without this, the Lambda ENIs could not open a connection to
# the Redis node they share the group with, game-rank-update would time out on
# every stream batch and the leaderboard would stay empty - with plan, apply
# and the function's creation all succeeding.
#
# All outbound rather than only the self-reference, because that is the egress
# the CloudFormation group actually had.
resource "aws_vpc_security_group_egress_rule" "all_outbound" {
  security_group_id = aws_security_group.gomoku_default.id
  description       = "All outbound, the default the CloudFormation group kept"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
