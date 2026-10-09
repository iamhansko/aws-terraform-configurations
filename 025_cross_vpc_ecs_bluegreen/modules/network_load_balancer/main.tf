# One network load balancer, its security group, one TCP listener and one target group.
#
# Instantiated twice by the root, and the two instances are what makes this project cross-VPC:
#
#   hub   internet-facing, in the hub VPC's public subnets, target_type ip. Its targets are the
#         private addresses of the app NLB in the other VPC, registered by the workbench because
#         they do not exist until that load balancer is provisioned. That registration is the
#         only reason the peering connection carries traffic.
#   app   internal, in the app VPC's private subnets, target_type alb. Its single target is the
#         internal ALB, attached by the root.
#
# Both are the same four resources with different inputs, which is why there is one module rather
# than a hub_nlb and an app_nlb that would have to be diffed to see how they differ.
resource "aws_security_group" "load_balancer_security_group" {
  name        = var.security_group_name
  description = var.security_group_description
  vpc_id      = var.vpc_id
  tags = {
    Name = var.security_group_name
  }
  # A network load balancer's security groups can only be set when it is created: AWS rejects
  # SetSecurityGroups on a load balancer that was created without any. Replacing this group
  # therefore has to replace the load balancer too, and create_before_destroy is what makes that
  # possible - the group cannot be deleted while the old load balancer still references it.
  lifecycle {
    create_before_destroy = true
  }
}
# Standalone rule resources rather than inline ingress/egress blocks (rules.md F-2).
#
# The _monolithic template gave each of its two NLB groups inline ingress blocks and no egress
# block. CloudFormation leaves the allow-all egress rule EC2 attaches to a new group alone when a
# template names only SecurityGroupIngress; Terraform's inline blocks are authoritative over the
# whole group, so omitting egress revokes that default instead of inheriting it.
#
# A load balancer with no egress rule is a specific and confusing failure: the listener accepts
# the connection, and then nothing reaches the target and every health check fails, so the console
# reports the targets unhealthy and says nothing about the group. Both groups here get an explicit
# egress rule for that reason.
resource "aws_vpc_security_group_ingress_rule" "load_balancer_cidr_ingress" {
  for_each = toset(var.ingress_cidr_blocks)

  security_group_id = aws_security_group.load_balancer_security_group.id
  description       = "Listener port from ${each.value}"
  ip_protocol       = "tcp"
  from_port         = var.listener_port
  to_port           = var.listener_port
  cidr_ipv4         = each.value
}
# Keyed by a caller-chosen label rather than taking a list, because every value in it is another
# module's output and so unknown at plan time - toset() on those values would make the key unknown
# too and plan would fail with "Invalid for_each argument" (rules.md B-8). The label also lands in
# the rule description, so a plan says which group each rule came from.
resource "aws_vpc_security_group_ingress_rule" "load_balancer_source_group_ingress" {
  for_each = var.ingress_source_security_groups

  security_group_id            = aws_security_group.load_balancer_security_group.id
  description                  = "Listener port from the ${each.key} security group"
  ip_protocol                  = "tcp"
  from_port                    = var.listener_port
  to_port                      = var.listener_port
  referenced_security_group_id = each.value
}
resource "aws_vpc_security_group_ingress_rule" "load_balancer_all_traffic_source_group_ingress" {
  for_each = var.all_traffic_source_security_groups

  security_group_id            = aws_security_group.load_balancer_security_group.id
  description                  = "All traffic from the ${each.key} security group"
  ip_protocol                  = "-1"
  referenced_security_group_id = each.value
}
resource "aws_vpc_security_group_egress_rule" "load_balancer_egress" {
  security_group_id = aws_security_group.load_balancer_security_group.id
  description       = "All outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
resource "aws_lb" "load_balancer" {
  name                             = var.name
  load_balancer_type               = "network"
  internal                         = var.internal
  subnets                          = var.subnet_ids
  security_groups                  = [aws_security_group.load_balancer_security_group.id]
  enable_cross_zone_load_balancing = var.enable_cross_zone_load_balancing
  enable_deletion_protection       = false
  tags = {
    Name = var.name
  }
}
resource "aws_lb_target_group" "load_balancer_target_group" {
  name        = var.target_group_name
  port        = var.target_port
  protocol    = "TCP"
  target_type = var.target_type
  vpc_id      = var.vpc_id
  # 30 seconds rather than the 300 second default, as the _monolithic template had it. A
  # blue/green switch and a destroy both wait out this delay per deregistered target.
  deregistration_delay = var.deregistration_delay
  health_check {
    # The protocol is set explicitly, and for the alb target type it has to be.
    #
    # The _monolithic template wrote only "path = /health" inside health_check on the app NLB's
    # target group. The provider then fills the protocol from the target group's own protocol,
    # which is TCP, and elbv2 rejects that combination for a target group whose target is an
    # application load balancer: a TCP health check cannot evaluate a path. The apply fails at
    # CreateTargetGroup with a ValidationError about the health check protocol, which reads as a
    # problem with the path rather than with the protocol that was never written down.
    #
    # The hub target group has no path - its targets are raw addresses - so it stays on TCP.
    protocol            = var.health_check_protocol
    path                = var.health_check_path
    port                = var.health_check_port
    interval            = var.health_check_interval
    healthy_threshold   = var.health_check_healthy_threshold
    unhealthy_threshold = var.health_check_unhealthy_threshold
  }
  tags = {
    Name = var.target_group_name
  }
  # A target group cannot be renamed, and the listener below holds a reference to it, so a change
  # that forces replacement has to create the new one first.
  lifecycle {
    create_before_destroy = true
  }
}
resource "aws_lb_listener" "load_balancer_listener" {
  load_balancer_arn = aws_lb.load_balancer.arn
  port              = var.listener_port
  protocol          = "TCP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.load_balancer_target_group.arn
  }
}
