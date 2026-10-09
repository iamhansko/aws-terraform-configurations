# The security group every ECS task's elastic network interface gets.
#
# One group for both application stacks, as the _monolithic template had it, and a module of its
# own rather than a resource inside modules/app_stack. Two stacks instantiating that module would
# produce two identical groups, and then the Aurora group would need an inbound rule per stack and
# the root would be passing a growing map of them around. The group also has to exist before
# either stack, because the Aurora module names it as an allowed source.
#
# The task definitions use awsvpc, which is what makes this the group that matters: a task gets its
# own interface in a private subnet, and this group - not the container instance group - is what
# the load balancer has to get past to reach the container port.
resource "aws_security_group" "ecs_service_security_group" {
  name        = var.name
  description = var.description
  vpc_id      = var.vpc_id
  tags = {
    Name = var.name
  }
}
# Standalone rule resources rather than inline ingress blocks (rules.md F-2).
#
# The _monolithic template gave this group three inline ingress blocks and no egress block.
# CloudFormation leaves EC2's allow-all outbound rule in place when a template names only
# SecurityGroupIngress; Terraform's inline blocks are authoritative over the whole group and revoke
# it instead.
#
# With awsvpc networking that is the single most damaging instance of the bug in this project.
# Every task's own interface loses outbound, so the execution role's ECR pull cannot leave, and the
# task stops with CannotPullContainerError against an image that is present and a role that is
# correct. The secret fetch and the FireLens upload fail the same way. The service then replaces
# the task and does it again, indefinitely, and apply reported success several minutes earlier.
resource "aws_vpc_security_group_ingress_rule" "ecs_service_source_group_ingress" {
  for_each = var.ingress_source_security_groups

  security_group_id            = aws_security_group.ecs_service_security_group.id
  description                  = "Container port from the ${each.key} security group"
  ip_protocol                  = "tcp"
  from_port                    = var.container_port
  to_port                      = var.container_port
  referenced_security_group_id = each.value
}
resource "aws_vpc_security_group_ingress_rule" "ecs_service_all_traffic_source_group_ingress" {
  for_each = var.all_traffic_source_security_groups

  security_group_id            = aws_security_group.ecs_service_security_group.id
  description                  = "All traffic from the ${each.key} security group"
  ip_protocol                  = "-1"
  referenced_security_group_id = each.value
}
resource "aws_vpc_security_group_egress_rule" "ecs_service_egress" {
  security_group_id = aws_security_group.ecs_service_security_group.id
  description       = "All outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
