# An internet-facing ALB in front of one ECS service: its security group, one target group, and either an
# HTTP listener or an HTTPS listener with an HTTP-to-HTTPS redirect beside it.
#
# One module for both of this project's load balancers. They differ in exactly one thing - whether a
# certificate is supplied - and that is a variable rather than two modules (rules.md B-4).
locals {
  # From the bool rather than from certificate_arn != null. The ARN comes out of a validation resource and is
  # unknown at plan, and count and for_each below need an answer at plan.
  https = var.enable_https
  # Every port a listener is created on, which is also every port the security group opens. One list, so a
  # listener cannot exist on a port the group does not open (rules.md G-1 makes the same point for a
  # controller-managed load balancer).
  listener_ports = local.https ? { https = 443, http = 80 } : { http = 80 }
}
resource "aws_security_group" "load_balancer" {
  name        = var.security_group_name
  description = "Security Group for the ${var.name} ALB"
  vpc_id      = var.vpc_id
  tags = {
    Name = var.security_group_name
  }
}
# Standalone rules rather than inline blocks (rules.md F-2), and conditional, as the _monolithic template's
# InboundFromAnywhere parameter made them.
resource "aws_vpc_security_group_ingress_rule" "listener_from_anywhere" {
  for_each          = local.listener_ports
  security_group_id = aws_security_group.load_balancer.id
  description       = var.allow_inbound_from_anywhere ? "${upper(each.key)} listener from anywhere" : "${upper(each.key)} listener from My IP"
  ip_protocol       = "tcp"
  from_port         = each.value
  to_port           = each.value
  cidr_ipv4         = var.allow_inbound_from_anywhere ? "0.0.0.0/0" : var.my_ip_cidr
}
# The rule the _monolithic template's groups were missing. They had ingress only, and Terraform removes the
# allow-all egress AWS puts on a new group, so neither ALB could open a connection to a target: every health
# check failed, every request was a 503, and the services looked healthy from ECS's side. Scoped to the
# target port inside the VPC, the only place an ALB ever needs to connect to.
resource "aws_vpc_security_group_egress_rule" "to_targets" {
  security_group_id = aws_security_group.load_balancer.id
  description       = "Target port inside the VPC"
  ip_protocol       = "tcp"
  from_port         = var.target_port
  to_port           = var.target_port
  cidr_ipv4         = var.vpc_cidr_block
}
resource "aws_lb" "load_balancer" {
  # CloudFormation generated the _monolithic template's two ALB names; Terraform does not require one, but an
  # unnamed ALB gets a random name that says nothing in the console, so the caller derives one.
  name               = var.name
  load_balancer_type = "application"
  internal           = false
  security_groups    = [aws_security_group.load_balancer.id]
  subnets            = var.subnet_ids
}
resource "aws_lb_target_group" "target_group" {
  name                 = var.name
  vpc_id               = var.vpc_id
  target_type          = "ip"
  protocol             = "HTTP"
  port                 = var.target_port
  deregistration_delay = var.deregistration_delay_seconds
  health_check {
    enabled             = true
    path                = var.health_check_path
    protocol            = "HTTP"
    matcher             = var.health_check_matcher
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}
resource "aws_lb_listener" "https" {
  count             = local.https ? 1 : 0
  load_balancer_arn = aws_lb.load_balancer.arn
  protocol          = "HTTPS"
  port              = 443
  ssl_policy        = var.ssl_policy
  certificate_arn   = var.certificate_arn
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.target_group.arn
  }
}
# Port 80 either forwards (no certificate) or redirects to HTTPS (with one), as the _monolithic template had
# the two ALBs respectively.
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.load_balancer.arn
  protocol          = "HTTP"
  port              = 80
  default_action {
    type             = local.https ? "redirect" : "forward"
    target_group_arn = local.https ? null : aws_lb_target_group.target_group.arn
    dynamic "redirect" {
      for_each = local.https ? [1] : []
      content {
        protocol    = "HTTPS"
        port        = "443"
        host        = "#{host}"
        path        = "/#{path}"
        query       = "#{query}"
        status_code = "HTTP_301"
      }
    }
  }
}
