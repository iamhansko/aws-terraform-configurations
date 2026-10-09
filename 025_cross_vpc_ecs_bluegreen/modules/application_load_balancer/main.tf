# The internal application load balancer every application stack hangs its listener rules off.
#
# This module owns the load balancer, its security group, the listener and the listener's default
# action. It deliberately owns no forwarding rule and no target group: those belong to a stack, so
# they live in modules/app_stack, which takes this listener's ARN as an input (rules.md B-6). The
# one exception is the fixed-response rule below, which belongs to no stack.
resource "aws_security_group" "application_load_balancer_security_group" {
  name        = var.security_group_name
  description = var.security_group_description
  vpc_id      = var.vpc_id
  tags = {
    Name = var.security_group_name
  }
  lifecycle {
    create_before_destroy = true
  }
}
# Standalone rule resources rather than inline ingress/egress blocks (rules.md F-2), and this is
# the group where that matters most in the project.
#
# The _monolithic template gave it two inline ingress blocks and no egress block, and
# CloudFormation's behaviour of leaving EC2's default allow-all egress rule in place when a
# template names only SecurityGroupIngress is what let that pass. Terraform's inline blocks are
# authoritative over the whole group, so the conversion revokes it.
#
# An application load balancer with no egress cannot reach its targets at all. Every target in
# every target group reports unhealthy with "Request timed out", the listener answers its own
# fixed-response default to everything that does arrive, and nothing in the console mentions the
# security group. Standalone rules make each direction a resource that is visibly present or
# visibly missing in a plan.
resource "aws_vpc_security_group_ingress_rule" "application_load_balancer_source_group_ingress" {
  for_each = var.ingress_source_security_groups

  security_group_id            = aws_security_group.application_load_balancer_security_group.id
  description                  = "Listener port from the ${each.key} security group"
  ip_protocol                  = "tcp"
  from_port                    = var.listener_port
  to_port                      = var.listener_port
  referenced_security_group_id = each.value
}
resource "aws_vpc_security_group_ingress_rule" "application_load_balancer_all_traffic_source_group_ingress" {
  for_each = var.all_traffic_source_security_groups

  security_group_id            = aws_security_group.application_load_balancer_security_group.id
  description                  = "All traffic from the ${each.key} security group"
  ip_protocol                  = "-1"
  referenced_security_group_id = each.value
}
resource "aws_vpc_security_group_egress_rule" "application_load_balancer_egress" {
  security_group_id = aws_security_group.application_load_balancer_security_group.id
  description       = "All outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
resource "aws_lb" "application_load_balancer" {
  name               = var.name
  load_balancer_type = "application"
  # Internal, as the _monolithic template had it, and that is the design rather than an omission:
  # the public entry point is the hub network load balancer in the other VPC. Making this
  # internet-facing would need public subnets and would bypass the whole cross-VPC path.
  internal                   = true
  subnets                    = var.subnet_ids
  security_groups            = [aws_security_group.application_load_balancer_security_group.id]
  enable_deletion_protection = false
  idle_timeout               = var.idle_timeout
  tags = {
    Name = var.name
  }
}
resource "aws_lb_listener" "application_load_balancer_listener" {
  load_balancer_arn = aws_lb.application_load_balancer.arn
  port              = var.listener_port
  protocol          = "HTTP"
  # The default action is a fixed 404, so a request matching no stack rule gets an answer rather
  # than a 503 from an empty default target group. CodeDeploy rewrites the stack rules during a
  # blue/green switch and never touches this.
  #
  # content_type is text/plain while the body is HTML, which is what the _monolithic template had.
  # A browser therefore shows the markup literally. It is left as the original wrote it; the
  # variables are there if the demo wants it rendered.
  default_action {
    type = "fixed-response"
    fixed_response {
      status_code  = var.not_found_status_code
      content_type = var.fixed_response_content_type
      message_body = var.not_found_message_body
    }
  }
}
# The one listener rule that belongs to no stack: a fixed 500 on a known path, so the demo can
# make the 5xx alarm and the dashboard widget fire without breaking an application.
#
# Its priority has to sit below every stack's rules. Nothing enforces that beyond the validation
# on the variable - two rules cannot share a priority, and elbv2 rejects the duplicate at apply
# with a PriorityInUse error naming only the second rule.
resource "aws_lb_listener_rule" "error_listener_rule" {
  listener_arn = aws_lb_listener.application_load_balancer_listener.arn
  priority     = var.error_rule_priority
  condition {
    path_pattern {
      values = [var.error_path]
    }
  }
  action {
    type = "fixed-response"
    fixed_response {
      status_code  = var.error_status_code
      content_type = var.fixed_response_content_type
      message_body = var.error_message_body
    }
  }
}
