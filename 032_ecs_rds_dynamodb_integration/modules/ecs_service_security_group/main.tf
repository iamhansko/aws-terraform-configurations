# One security group for all three services' task ENIs, as the _monolithic template declared it.
#
# A separate module rather than part of ecs_service, because the group is shared: the ecs_service module is
# instantiated once per application, and putting the group inside it would create three identical groups and
# make each application's rules a different resource address. The three applications also have identical
# network requirements - inbound on one port, outbound everywhere - so there is nothing per-application to
# express.
#
# With awsvpc networking this group is attached to each task's own ENI, which is why it is the group that
# matters for reaching a container and the container instance group is not.
resource "aws_security_group" "ecs_service_security_group" {
  name        = var.name
  description = var.description
  vpc_id      = var.vpc_id
  tags = {
    Name = var.name
  }
}
# Standalone rule resources rather than inline ingress/egress blocks (rules.md F-2), and the egress rule is
# the one the tasks cannot run without.
#
# The template gave this group two inline ingress blocks and no egress block. In CloudFormation that leaves
# the allow-all egress rule AWS attaches to a new group in place, because AWS::EC2::SecurityGroup only takes
# over the rules a template names; Terraform's inline ingress/egress are attributes-as-blocks and
# authoritative over the whole group, so naming any rule revokes it.
#
# For a task ENI that removes everything the containers do outside the VPC: the product application's
# DynamoDB calls, the execution role's Secrets Manager read that injects the database password, and the
# awslogs driver's connection to CloudWatch Logs. The last two happen before the container starts, so the
# task does not fail at runtime - it never reaches runtime, and stops with a ResourceInitializationError
# naming the secret or the log driver. Which is a message about a secret, for a networking fault.
resource "aws_vpc_security_group_egress_rule" "ecs_service_egress" {
  security_group_id = aws_security_group.ecs_service_security_group.id
  description       = "All outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
# The template's first ingress block: all traffic from the VPC CIDR. These are literals in configuration, so
# toset is safe here - unlike a security group ID arriving from another module (rules.md B-8).
resource "aws_vpc_security_group_ingress_rule" "ecs_service_cidr_ingress" {
  for_each = toset(var.all_traffic_cidr_blocks)

  security_group_id = aws_security_group.ecs_service_security_group.id
  description       = "All traffic from ${each.value}"
  ip_protocol       = "-1"
  cidr_ipv4         = each.value
}
# The template's second ingress block: the application port from the workbench's security group. Redundant
# while the rule above admits the whole VPC and the workbench is inside it, and kept because it is the rule
# that still works when a caller narrows all_traffic_cidr_blocks - which is the first thing to narrow here.
#
# A map keyed by a caller-chosen label rather than a list, because these IDs are another module's output and
# unknown at plan time (rules.md B-8).
resource "aws_vpc_security_group_ingress_rule" "ecs_service_port_source_group_ingress" {
  for_each = var.port_source_security_groups

  security_group_id            = aws_security_group.ecs_service_security_group.id
  description                  = "Application port from the ${each.key} security group"
  ip_protocol                  = "tcp"
  from_port                    = var.port
  to_port                      = var.port
  referenced_security_group_id = each.value
}
