# The internet-facing ALB, its security group, the one target group the service registers into and the
# listener that forwards to it.
#
# All four are here because the listener is only meaningful with the group it forwards to, and the group is
# only meaningful with the port its health check uses - splitting them would make the caller restate the
# pairing in three places.
resource "aws_security_group" "load_balancer" {
  name = var.security_group_name
  # A description that says what the group is for. The _monolithic template's was the literal string
  # "Security Group", which is what a converter writes when the source had nothing to say. It is worth
  # getting right on the first apply: EC2 has no API for changing a group's description, so the provider
  # marks this attribute as forcing replacement, and a security group referenced by a load balancer, a
  # listener and another group's rule is awkward to replace (rules.md F-1).
  description = var.security_group_description
  vpc_id      = var.vpc_id
  tags = {
    Name = var.security_group_name
  }
}
# Standalone rule resources rather than inline ingress/egress blocks (rules.md F-2), and the egress rule is
# a fix rather than a transcription.
#
# The _monolithic template declared this group with one inline ingress block and no egress block at all. In
# CloudFormation that is a group that keeps the allow-all egress rule EC2 attaches at creation, because
# AWS::EC2::SecurityGroup only takes over the rules a template actually names. Terraform's inline
# ingress/egress are attributes-as-blocks and authoritative over the whole group, so omitting egress does
# not inherit that default - the provider revokes it.
#
# For an ALB that is the difference between the project working and a project that reports success and
# serves nothing. The load balancer can accept a connection and cannot open one, so every health check
# fails with Target.Timeout and every request comes back 502 or 503 while the ECS service itself is healthy
# and the tasks are running fine. Nothing in that picture points at the load balancer's own egress.
resource "aws_vpc_security_group_ingress_rule" "listener_ingress" {
  for_each = toset(var.ingress_cidr_blocks)

  security_group_id = aws_security_group.load_balancer.id
  description       = "Listener port from ${each.value}"
  ip_protocol       = "tcp"
  from_port         = var.listener_port
  to_port           = var.listener_port
  cidr_ipv4         = each.value
}
# Scoped to the target port inside the VPC rather than opened to 0.0.0.0/0. An ALB only ever connects to its
# targets, and its targets are addresses in this VPC - the tasks' network interfaces, which target_type ip
# registers by private address even though they also carry a public one.
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
resource "aws_lb_target_group" "target_group" {
  name     = var.target_group_name
  vpc_id   = var.vpc_id
  port     = var.target_port
  protocol = "HTTP"
  # ip, as the _monolithic template had it, and it is the only correct value here: an awsvpc task has no
  # instance to register, so a Fargate service can register targets only by address.
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
    target_group_arn = aws_lb_target_group.target_group.arn
  }
}
