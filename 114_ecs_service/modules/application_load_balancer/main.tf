# The internet-facing ALB, its two target groups and the listener rule the ECS service names as its
# production rule.
#
# Both target groups are here, and so is the rule, because the service's load_balancer block names all three
# together: the primary group the tasks register into, the alternate group and the production listener rule
# its advanced_configuration points at. Splitting them would make the caller restate the pairing.
resource "aws_security_group" "load_balancer" {
  name        = var.security_group_name
  description = "Security Group for the public ALB in front of the ECS service"
  vpc_id      = var.vpc_id
  tags = {
    Name = var.security_group_name
  }
}
# Standalone rules rather than inline blocks (rules.md F-2). The listener port from anywhere is conditional,
# as the _monolithic template's InboundFromAnywhere parameter made it.
resource "aws_vpc_security_group_ingress_rule" "listener_from_anywhere" {
  count             = var.allow_inbound_from_anywhere ? 1 : 0
  security_group_id = aws_security_group.load_balancer.id
  description       = "Listener port from anywhere"
  ip_protocol       = "tcp"
  from_port         = var.listener_port
  to_port           = var.listener_port
  cidr_ipv4         = "0.0.0.0/0"
}
# The rule the _monolithic template was missing entirely. Its group had ingress only, and Terraform removes
# the allow-all egress AWS puts on a new group, so the ALB could not open a connection to a single target:
# every health check failed and every request was a 502 or a 503, with the service itself healthy. Scoped to
# the target port inside the VPC, which is the only place an ALB ever needs to connect to.
resource "aws_vpc_security_group_egress_rule" "to_targets" {
  security_group_id = aws_security_group.load_balancer.id
  description       = "Target port inside the VPC"
  ip_protocol       = "tcp"
  from_port         = var.target_port
  to_port           = var.target_port
  cidr_ipv4         = var.vpc_cidr_block
}
resource "aws_lb" "load_balancer" {
  name               = var.name
  load_balancer_type = "application"
  internal           = false
  security_groups    = [aws_security_group.load_balancer.id]
  subnets            = var.subnet_ids
}
# for_each over two literal keys rather than two copied resource blocks. The keys are configuration, not
# apply-time values, so they are safe resource addresses (rules.md B-8).
resource "aws_lb_target_group" "target_group" {
  for_each    = tomap(var.target_group_names)
  name        = each.value
  vpc_id      = var.vpc_id
  port        = var.target_port
  protocol    = "HTTP"
  target_type = "ip"
  health_check {
    path     = var.health_check_path
    protocol = "HTTP"
    port     = var.target_port
  }
}
resource "aws_lb_listener" "listener" {
  load_balancer_arn = aws_lb.load_balancer.arn
  port              = var.listener_port
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.target_group["primary"].arn
  }
}
# The rule the service's advanced_configuration names as production_listener_rule. It forwards to the
# primary group, which is the group the service registers its tasks into.
resource "aws_lb_listener_rule" "production" {
  listener_arn = aws_lb_listener.listener.arn
  priority     = var.production_rule_priority
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.target_group["primary"].arn
  }
  condition {
    path_pattern {
      values = var.production_rule_path_patterns
    }
  }
}
