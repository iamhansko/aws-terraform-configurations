# The load balancer Argo Rollouts switches traffic on. Created by Terraform rather
# than by the AWS Load Balancer Controller, because a Rollout's blue/green strategy
# names an existing target group ARN - it does not provision one. The _monolithic
# template built these three with "aws elbv2 create-*" inside an SSM association and
# then sed-substituted the resulting ARN into a YAML file on disk, which left no
# connection between the load balancer and anything Terraform tracked.
#
# What Terraform owns here is the shell: load balancer, one target group, one
# listener. What it does not own is which pods are registered in that target group -
# Argo Rollouts moves targets between the active and preview ReplicaSets, and that
# is the whole point of the demo. Hence the lifecycle blocks below.
resource "aws_lb" "alb" {
  name               = var.name
  load_balancer_type = "application"
  internal           = var.internal
  subnets            = var.subnet_ids
  security_groups    = var.security_group_ids

  tags = {
    Name = var.name
  }

  lifecycle {
    # The security group list is the one attribute something outside Terraform is
    # likely to touch here: the _monolithic template attached the EKS cluster
    # security group by looking it up at run time, and the AWS Load Balancer
    # Controller adds rules to whatever group is attached (rules.md F-2).
    ignore_changes = [security_groups]
  }
}
resource "aws_lb_target_group" "active" {
  name        = var.target_group_name
  port        = var.port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    path                = var.health_check_path
    matcher             = var.health_check_matcher
    interval            = var.health_check_interval_seconds
    healthy_threshold   = var.health_check_healthy_threshold
    unhealthy_threshold = var.health_check_unhealthy_threshold
  }

  tags = {
    Name = var.target_group_name
  }

  lifecycle {
    # Argo Rollouts registers and deregisters pod IPs in this target group as it
    # promotes a new version, and the AWS Load Balancer Controller writes the
    # TargetGroupBinding that does it. Terraform must not put the membership back
    # the way it found it, or a promotion would be undone by the next plan
    # (rules.md G-3 applies the same reasoning to a load balancer the controller
    # adopts).
    ignore_changes = [tags, tags_all]
  }
}
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.alb.arn
  port              = var.port
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.active.arn
  }

  lifecycle {
    # Argo Rollouts rewrites the listener's forward action to shift traffic between
    # the active and preview target groups during a blue/green promotion. Leaving
    # default_action under Terraform's control would make every plan want to point
    # it back at the active group.
    ignore_changes = [default_action]
  }
}
