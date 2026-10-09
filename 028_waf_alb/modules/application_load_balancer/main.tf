# The load balancer, its frontend security group, one target group and one HTTP listener.
#
# This is everything the _monolithic template declared for the ALB except the target registration, which is
# in the root. That one resource is there because it names a target group from this module and an instance
# from another, and a module that referenced the instance module's output while the instance module
# referenced this module's security group id would be a graph cycle - Terraform reports
# "Error: Cycle: module.app_server_ec2.var... , module.application_load_balancer.output..." and refuses to
# plan, which terraform validate also catches. Joining two modules is the root's job in any case
# (rules.md C-1).
#
# Why the WAF association is not here: a web ACL is a regional resource of its own with its own lifecycle,
# and this module has no opinion about whether anything is filtering in front of it. See
# modules/web_application_firewall/main.tf.
resource "aws_security_group" "load_balancer_security_group" {
  name        = var.security_group_name
  name_prefix = var.security_group_name == null ? var.security_group_name_prefix : null
  description = var.security_group_description
  vpc_id      = var.vpc_id
  tags = {
    Name = coalesce(var.security_group_name, var.security_group_name_prefix)
  }

  # The group is the source of the app server's ingress rule, so it cannot be deleted while that rule
  # references it. Nothing outside Terraform adds rules to this group - there is no load balancer controller
  # here - but a destroy that removes the groups in the wrong order still stops at DependencyViolation, and
  # this revokes the attached rules first (rules.md F-2).
  revoke_rules_on_delete = var.revoke_rules_on_delete
}
# Standalone rule resources rather than inline ingress/egress blocks, and in this project that is a bug fix
# rather than a style choice (rules.md F-2).
#
# The _monolithic template declared three security groups with four inline ingress blocks between them and
# not one egress block. CloudFormation's AWS::EC2::SecurityGroup leaves the allow-all egress rule that EC2
# attaches to every new group alone when a template names only SecurityGroupIngress, so the source template
# never had to spell outbound access out. Terraform's inline blocks are attributes-as-blocks and are
# authoritative over the whole group: converting the ingress blocks across without adding an egress block
# does not inherit that default, it revokes it. All three groups would have come out with no outbound access
# at all.
#
# For this group specifically that is the difference between a working demo and a 503. The load balancer's
# nodes make the health check request and the forwarded request outbound from this group to the target on
# its traffic port; with egress revoked every target reads unhealthy, the listener has nothing to forward
# to, and the ALB answers 503 for every request - including the ones the web ACL allowed, so the demo's
# "allowed" and "blocked" cases become 503 and 403 and the point is lost. terraform apply reports success
# throughout.
#
# This defect broke 101_ubuntu_xrdp and was found twice in 103_ecs_volumes. Every group in this project now
# declares both directions as resources that a plan either shows or visibly omits.
resource "aws_vpc_security_group_egress_rule" "load_balancer_egress" {
  security_group_id = aws_security_group.load_balancer_security_group.id
  description       = "All outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
# for_each over the CIDR list rather than one rule per literal, and toset() is correct here because these
# are configuration literals and so are known at plan time (rules.md B-7/B-8). each.value in the description
# is what makes a plan say which source a rule is for.
resource "aws_vpc_security_group_ingress_rule" "load_balancer_listener_ingress" {
  for_each = toset(var.ingress_cidr_blocks)

  security_group_id = aws_security_group.load_balancer_security_group.id
  description       = "Listener port ${var.listener_port} from ${each.value}"
  ip_protocol       = "tcp"
  from_port         = var.listener_port
  to_port           = var.listener_port
  cidr_ipv4         = each.value
}
resource "aws_lb" "load_balancer" {
  # A generated name by default, where the _monolithic template used the literal "alb".
  #
  # A fixed name is unique per account and region, so a second copy of this project fails the create call
  # with DuplicateLoadBalancerName - and the same template fixed the target group's name to "alb-tg", so
  # both collide. name_prefix is the provider's own way of avoiding that; note that it is capped at six
  # characters, which is why the prefix defaults are short. The same reasoning is in modules/key_pair.
  name        = var.name
  name_prefix = var.name == null ? var.name_prefix : null

  load_balancer_type = "application"
  # false, as the template had it: an internet-facing scheme, which requires public subnets. The web ACL in
  # front of this is the only thing standing between the internet and a deliberately SQL-injectable Flask
  # app, which is the demo and also the reason the app's own security group is closed by default.
  internal        = var.internal
  subnets         = var.subnet_ids
  security_groups = [aws_security_group.load_balancer_security_group.id]

  # false, which is the default and what the template had. Worth stating rather than omitting: with it true
  # terraform destroy fails on the load balancer and leaves the web ACL, the target group and the instances
  # behind it in place, and the error names deletion protection rather than the configuration that set it.
  enable_deletion_protection = var.enable_deletion_protection

  tags = {
    Name = coalesce(var.name, var.name_prefix)
  }
}
resource "aws_lb_target_group" "target_group" {
  name        = var.target_group_name
  name_prefix = var.target_group_name == null ? var.target_group_name_prefix : null

  port        = var.target_port
  protocol    = var.target_protocol
  vpc_id      = var.vpc_id
  target_type = var.target_type

  # The _monolithic template set path and nothing else, so every other value here is the AWS default written
  # down rather than a change. They are worth having in the configuration because they are the whole
  # explanation for the gap between "apply finished" and "the URL answers": with these defaults a freshly
  # registered target needs healthy_threshold successful checks at interval seconds apart before the
  # listener will forward to it, which is why the root publishes a describe-target-health command instead of
  # expecting the first curl to work.
  #
  # The path matters more than it looks. It has to be something the app answers 200 to, and the Flask app
  # behind this serves its form on "/" - so a health check pointed at a path the app does not route reads
  # unhealthy forever while the app is perfectly fine, and the symptom is a 503 from the ALB.
  health_check {
    path                = var.health_check_path
    matcher             = var.health_check_matcher
    interval            = var.health_check_interval_seconds
    timeout             = var.health_check_timeout_seconds
    healthy_threshold   = var.health_check_healthy_threshold
    unhealthy_threshold = var.health_check_unhealthy_threshold
  }

  tags = {
    Name = coalesce(var.target_group_name, var.target_group_name_prefix)
  }
}
resource "aws_lb_listener" "listener" {
  load_balancer_arn = aws_lb.load_balancer.arn
  port              = var.listener_port
  # HTTP, as the template had it. Not an oversight to leave at HTTP for this project: WAF inspects the
  # request after the listener has terminated it, so HTTPS would change nothing about what the web ACL sees,
  # and an HTTPS listener needs an ACM certificate and therefore a domain. It does mean the injection probes
  # the demo sends travel in clear text, which is of no consequence against a throwaway SQLite database.
  protocol = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.target_group.arn
  }
}
locals {
  # http because the listener is HTTP. No port in the URL: the listener is on var.listener_port and a
  # non-default port would have to appear here, so this is derived rather than written out (rules.md B-5).
  url = "http://${aws_lb.load_balancer.dns_name}${var.listener_port == 80 ? "" : ":${var.listener_port}"}"
  # Deliberately no curl commands here. They need the app's routes and query parameter names as well as this
  # URL, and this module has no business knowing that the thing behind it is a Flask app with a /lookup
  # route - it takes a target group port and nothing else. The root owns that join (rules.md C-1).
  target_health_command = "aws elbv2 describe-target-health --target-group-arn ${aws_lb_target_group.target_group.arn} --query 'TargetHealthDescriptions[].[Target.Id,Target.Port,TargetHealth.State,TargetHealth.Reason]' --output table"
}
