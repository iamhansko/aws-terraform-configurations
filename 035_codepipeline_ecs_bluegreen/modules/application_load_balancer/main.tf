# The load balancer, its two target groups and its listener in one module, which is a deliberate
# boundary rather than a convenience.
#
# CodeDeploy names all three as a single unit: load_balancer_info.target_group_pair_info takes the
# listener ARN under prod_traffic_route and both target groups beside it, and what a deployment does is
# rewrite that listener's default rule, and any other rule on it that forwards to the live target group,
# from one of them to the other. Splitting the listener from the target groups would put the two halves
# of one controller-owned swap in two different modules, and the reader looking for "what does a
# deployment change" would have to find both.
#
# The security group lives here too, which is this repository's convention: a group belongs with the
# thing it protects.
resource "aws_security_group" "load_balancer_security_group" {
  name        = var.security_group_name
  description = var.security_group_description
  vpc_id      = var.vpc_id
  # This is not the controller case rules.md F-2's last paragraph describes - no controller or AWS
  # service adds rules to this group, and the only rule anywhere that references it is the task group's
  # inbound rule, which Terraform owns and removes first.
  #
  # It is set because the flag changes nothing except the order Terraform deletes in - it is not a
  # Forces new resource field, unlike name and description (rules.md F-1) - and this is the one group in
  # the project somebody is likely to add a rule to by hand: it is the public entry point, so a rule
  # opened while working out why the demo URL does not answer is the plausible thing to leave behind,
  # and AWS then refuses to delete the group.
  revoke_rules_on_delete = var.revoke_rules_on_delete
  tags = {
    Name = var.security_group_name
  }
}
# Standalone rule resources rather than inline ingress/egress blocks (rules.md F-2), and the egress rule
# below is a fix rather than a transcription.
#
# The _monolithic template gave this group one inline ingress block and no egress block at all. In
# CloudFormation an AWS::EC2::SecurityGroup that names only SecurityGroupIngress keeps the allow-all
# outbound rule EC2 adds at creation; Terraform's inline ingress and egress are attributes-as-blocks
# and authoritative over the whole group, so declaring either one revokes that default.
#
# On a load balancer that is the most confusing possible place for it. Requests from the internet still
# arrive - inbound is intact - and the load balancer cannot open a connection to any target, so every
# request ends in a 502 after the connection attempt times out. The target group reports all targets
# unhealthy for the same reason, because the health check is an outbound connection too. Nothing in
# that picture points at this group: it looks exactly like an application that is not listening.
#
# All four groups in this project had the same hole. See the bastion, container instance and task
# groups for what it cost each of them.
resource "aws_vpc_security_group_egress_rule" "load_balancer_egress" {
  security_group_id = aws_security_group.load_balancer_security_group.id
  description       = "All outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
# The public entry point. for_each over the CIDR list rather than one resource per source; these are
# literals in configuration, so toset is safe (rules.md B-8).
resource "aws_vpc_security_group_ingress_rule" "load_balancer_cidr_ingress" {
  for_each = toset(var.ingress_cidr_blocks)

  security_group_id = aws_security_group.load_balancer_security_group.id
  description       = "Listener port from ${each.value}"
  ip_protocol       = "tcp"
  from_port         = var.listener_port
  to_port           = var.listener_port
  cidr_ipv4         = each.value
}
# Nothing in this project passes a source group, but the hook exists because the demo's own listener
# rule invites adding one. A map keyed by a caller-chosen label rather than a list, because such an ID
# would come from another module and be unknown at plan time (rules.md B-8).
resource "aws_vpc_security_group_ingress_rule" "load_balancer_source_group_ingress" {
  for_each = var.ingress_source_security_groups

  security_group_id            = aws_security_group.load_balancer_security_group.id
  description                  = "Listener port from the ${each.key} security group"
  ip_protocol                  = "tcp"
  from_port                    = var.listener_port
  to_port                      = var.listener_port
  referenced_security_group_id = each.value
}
# Two target groups, which is what CodeDeploy needs rather than a redundancy.
#
# A blue/green deployment holds one of them live while the replacement task set registers into the
# other, then rewrites the listener's default rule to point at it. Both have to exist up front and both
# have to be the same shape, so the only difference between these two resources is the name.
#
# target_type is ip, and that is the decision in this module rather than a default. The task definition
# uses awsvpc network mode, so each task gets its own elastic network interface with its own address in
# a private subnet and there is no port translation - the load balancer connects straight to the task's
# container port. The alternative, target_type instance, registers container instances on a host port
# that ECS assigns from the ephemeral range, which awsvpc does not do at all: with awsvpc, hostPort has
# to equal containerPort and the thing holding that port is the task's interface, not the instance. So
# instance here would register the right instances on the wrong port, the health check would fail
# against every one of them, and the service would look like it had never started.
resource "aws_lb_target_group" "blue" {
  name            = var.blue_target_group_name
  vpc_id          = var.vpc_id
  port            = var.target_port
  protocol        = var.target_protocol
  target_type     = var.target_type
  ip_address_type = var.target_ip_address_type
  health_check {
    enabled             = var.health_check_enabled
    path                = var.health_check_path
    protocol            = var.target_protocol
    port                = tostring(var.target_port)
    interval            = var.health_check_interval
    timeout             = var.health_check_timeout
    healthy_threshold   = var.health_check_healthy_threshold
    unhealthy_threshold = var.health_check_unhealthy_threshold
    matcher             = var.health_check_matcher
  }
  tags = {
    Name = var.blue_target_group_name
  }
}
resource "aws_lb_target_group" "green" {
  name            = var.green_target_group_name
  vpc_id          = var.vpc_id
  port            = var.target_port
  protocol        = var.target_protocol
  target_type     = var.target_type
  ip_address_type = var.target_ip_address_type
  health_check {
    enabled             = var.health_check_enabled
    path                = var.health_check_path
    protocol            = var.target_protocol
    port                = tostring(var.target_port)
    interval            = var.health_check_interval
    timeout             = var.health_check_timeout
    healthy_threshold   = var.health_check_healthy_threshold
    unhealthy_threshold = var.health_check_unhealthy_threshold
    matcher             = var.health_check_matcher
  }
  tags = {
    Name = var.green_target_group_name
  }
}
resource "aws_lb" "load_balancer" {
  name               = var.name
  load_balancer_type = "application"
  internal           = var.internal
  ip_address_type    = var.ip_address_type
  subnets            = var.subnet_ids
  security_groups    = [aws_security_group.load_balancer_security_group.id]
  idle_timeout       = var.idle_timeout
  tags = {
    Name = var.name
  }

  # The group's own rules before the load balancer, so that it is never briefly listening with no
  # outbound path. Nothing in this resource references the rules - security_groups references the group -
  # so the ordering has to be stated (rules.md D-1).
  depends_on = [
    aws_vpc_security_group_egress_rule.load_balancer_egress,
    aws_vpc_security_group_ingress_rule.load_balancer_cidr_ingress,
  ]
}
# The production listener. Its default action is one of the two fields in this project that Terraform
# and CodeDeploy both write; the other is the action of the User-Agent rule below.
resource "aws_lb_listener" "listener" {
  load_balancer_arn = aws_lb.load_balancer.arn
  port              = var.listener_port
  protocol          = var.listener_protocol
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.blue.arn
  }

  lifecycle {
    # A CodeDeploy ECS blue/green deployment finishes by rewriting this listener's default rule from the
    # blue target group to the green one - that rewrite is the traffic shift, and it is why the
    # deployment group's service role needs elasticloadbalancing:ModifyListener and ModifyRule.
    #
    # Terraform recorded blue. Without this, the first plan after a successful deployment proposes
    # changing the default action back - and applying that plan moves live traffic to the task set
    # CodeDeploy has already drained and terminated, with termination_wait_time_in_minutes at zero
    # meaning there is nothing left behind it. Every request on the demo URL becomes a 503 until
    # somebody notices, and CodeDeploy still reports the deployment as succeeded.
    #
    # This is rules.md E-8's argument for excluding the path a controller owns rather than freezing the
    # resource, at the granularity the provider allows: an aws_lb_listener's whole default action is one
    # attribute, so naming it is as narrow as it gets here. The port, the protocol and the load balancer
    # stay tracked, so a change to any of them is still a plan.
    #
    # The value written above is therefore the starting point only - blue at first apply, and whatever
    # the last deployment chose after that.
    ignore_changes = [default_action]
  }
}
# The User-Agent rule, reproduced from the _monolithic template, and it needs a warning rather than a
# description. Two separate things are true about it.
#
# First, as written it can never match. An ALB http-header condition is a whole-value comparison with
# explicit wildcards - AWS documents the comparison strings as case insensitive with * matching zero or
# more characters and ? matching exactly one - so the value "Mozilla" matches a User-Agent header whose
# entire value is "Mozilla" and not the "Mozilla/5.0 (...)" that every real browser sends. The rule is
# therefore dead configuration that still occupies priority 1, and every request reaches the listener's
# default action instead. If a per-client route is actually wanted, the fix is a distinct path or a
# header the client controls, not a wildcarded User-Agent.
#
# Second, and this is the part that breaks deployments: its action has two owners, exactly like the
# listener's default action above. prod_traffic_route names only the listener, but CodeDeploy also
# rewrites the rules on that listener that forward to the live target group. CloudTrail shows its
# service role calling ModifyRule on this rule twice - once at CreateDeploymentGroup, normalising it onto the live
# target group, and again at the traffic shift, in the same second as the ModifyListener that moved the
# default action from blue to green. So after the first deployment this rule forwards to green, and
# Terraform recorded blue.
#
# Without ignore_changes the next apply "fixes" that, putting the rule back on blue, where there is no
# task set left (termination_wait_time_in_minutes is zero). Nothing fails at that point - the rule never
# matches, so no request notices. The next deployment does: CodeDeploy checks the listener's rules
# before it creates the replacement task set and stops with
#
#   ELASTIC_LOAD_BALANCING_INVALID: The ELB could not be updated due to the following error: Primary
#   taskset target group must be behind listener arn:...:listener-rule/app/<alb>/<lb-id>/<listener-id>/<rule-id>
#
# naming this rule, and every deployment after it fails the same way until the rule is pointed back at
# the target group the primary task set is registered in. The ARN in that message is a listener-rule
# ARN, not the listener's, which is the clue that the default action is not the problem.
#
# Same argument as rules.md E-8 at the granularity the provider allows: the whole forward configuration
# is one attribute, so the action is ignored and the priority, the listener and the condition stay
# tracked. The target group written below is the starting point only - blue at first apply, and
# whatever the last deployment chose after that.
resource "aws_lb_listener_rule" "user_agent" {
  count = var.create_user_agent_rule ? 1 : 0

  listener_arn = aws_lb_listener.listener.arn
  priority     = var.user_agent_rule_priority
  condition {
    http_header {
      http_header_name = var.user_agent_rule_header_name
      values           = var.user_agent_rule_values
    }
  }
  # The plain forward form, where the _monolithic template nested a forward block with one target group
  # at weight 1. For a single target group the two are the same action; the nested form additionally
  # makes elbv2 return a weighted forward configuration that the provider then has to reconcile against
  # a configuration that only names one group, which is a well-known source of a diff that never
  # settles. Weights are what a canary needs, and this rule is not one.
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.blue.arn
  }

  lifecycle {
    # CodeDeploy rewrites this action on every traffic shift - see the comment above the resource.
    ignore_changes = [action]
  }
}
