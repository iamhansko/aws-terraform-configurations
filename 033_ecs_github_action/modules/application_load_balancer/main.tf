# The internet-facing ALB, the blue/green target group pair and the single production listener.
#
# All three are in one module because CodeDeploy's load_balancer_info names them together: the listener is
# the production traffic route and the two groups are the pair it swaps between. Splitting them would make
# the caller restate the pairing, and a pairing restated in two places is the failure mode this whole
# project is built around - see the deployment group module.
resource "aws_security_group" "load_balancer_security_group" {
  name        = var.security_group_name
  description = var.security_group_description
  vpc_id      = var.vpc_id
  # Only changes Terraform's delete behaviour; it does not replace the group (rules.md F-2). Nothing adds
  # rules here that Terraform does not track - CodeDeploy reshuffles the target groups behind this
  # listener but never touches a security group - so this is defensive. It stays on because the service
  # group's ingress rule references this group, and revoking this group's own rules first removes one way
  # for a destroy to stall on a reference that is being unpicked at the same time.
  revoke_rules_on_delete = var.revoke_rules_on_delete
  tags = {
    Name = var.security_group_name
  }
}
# Standalone rules rather than inline blocks (rules.md F-2).
resource "aws_vpc_security_group_ingress_rule" "listener_from_anywhere" {
  count             = var.allow_inbound_from_anywhere ? 1 : 0
  security_group_id = aws_security_group.load_balancer_security_group.id
  description       = "Listener port from anywhere"
  ip_protocol       = "tcp"
  from_port         = var.listener_port
  to_port           = var.listener_port
  cidr_ipv4         = "0.0.0.0/0"
}
# The rule the _monolithic template was missing entirely. Its group had one ingress block and no egress
# block, and Terraform revokes the allow-all egress AWS puts on a new group as soon as any inline rule is
# declared - so that ALB could not open a connection to a single target. Every health check fails, every
# request is a 502 or a 503, and the ECS service reports itself healthy throughout.
#
# Scoped to the target port inside the VPC, which is the only place this ALB ever connects to: the targets
# are awsvpc task ENIs in the private subnets, and the health check uses the same port as the traffic.
resource "aws_vpc_security_group_egress_rule" "to_targets" {
  security_group_id = aws_security_group.load_balancer_security_group.id
  description       = "Target port inside the VPC"
  ip_protocol       = "tcp"
  from_port         = var.target_port
  to_port           = var.target_port
  cidr_ipv4         = var.vpc_cidr_block
}
resource "aws_lb" "load_balancer" {
  name               = var.name
  load_balancer_type = "application"
  internal           = var.internal
  security_groups    = [aws_security_group.load_balancer_security_group.id]
  subnets            = var.subnet_ids
}
# for_each over two literal keys rather than two copied resource blocks. The keys are configuration, not
# apply-time values, so they are safe resource addresses (rules.md B-8).
#
# target_type is "ip" and has to be. The task definition uses network_mode awsvpc, so each task gets its
# own ENI and registers by address; ECS rejects a service whose target group is target_type "instance"
# against an awsvpc task definition outright. "instance" would be the real alternative on an
# ECS-on-EC2 cluster like this one if the tasks used bridge or host networking, and then the registered
# target would be the container instance on its mapped host port instead.
resource "aws_lb_target_group" "target_group" {
  for_each    = var.target_group_names
  name        = each.value
  vpc_id      = var.vpc_id
  port        = var.target_port
  protocol    = "HTTP"
  target_type = var.target_type
  health_check {
    enabled  = true
    path     = var.health_check_path
    protocol = "HTTP"
    port     = "traffic-port"
  }
  # The listener's default action and the service's load_balancer block both name a target group by ARN, so
  # a group cannot be replaced in place while either still points at it. create_before_destroy makes a
  # rename or a port change roll forward instead of deadlocking.
  lifecycle {
    create_before_destroy = true
  }
}
# The production traffic route. The deployment group names this listener, and the service registers into
# whichever group it currently forwards to.
resource "aws_lb_listener" "listener" {
  load_balancer_arn = aws_lb.load_balancer.arn
  port              = var.listener_port
  protocol          = "HTTP"
  # The blue group, which is the same group the service's load_balancer block names. The three have to
  # agree on which group is live at creation: the service registers its tasks into the group it names, and
  # CodeDeploy works out the other half of the pair from what the listener currently forwards to.
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.target_group[var.initial_target_group_key].arn
  }
  lifecycle {
    # The field CodeDeploy owns from the first deployment onward.
    #
    # A blue/green deployment's whole mechanism is rewriting this listener to forward to the replacement
    # group. Terraform recorded the blue group's ARN, so without this every plan after a successful
    # deployment proposes pointing the listener back at blue - and applying it sends production traffic to
    # the task set CodeDeploy has already terminated, while CodeDeploy still reports the deployment as
    # succeeded.
    #
    # This is rules.md E-8's argument applied to an ALB listener rather than a Kubernetes object: exclude
    # the path the controller owns and keep tracking the rest. default_action is a single attribute here, so
    # naming it is as narrow as the resource allows - the port, the protocol and the load balancer stay
    # tracked.
    ignore_changes = [default_action]
  }
}
