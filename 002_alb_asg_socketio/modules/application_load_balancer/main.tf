resource "aws_security_group" "application_load_balancer_security_group" {
  description = "Security Group for Application Load Balancer"
  name        = "alb-sg"
  vpc_id      = var.vpc_id

  ingress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = var.listener_port
    protocol    = "tcp"
    to_port     = var.listener_port
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "alb-sg"
  }
}

resource "aws_lb" "application_load_balancer" {
  name               = "stem-alb"
  ip_address_type    = "ipv4"
  load_balancer_type = "application"
  internal           = false
  security_groups    = [aws_security_group.application_load_balancer_security_group.id]
  subnets            = var.subnet_ids
}

resource "aws_lb_target_group" "target_group" {
  name            = "stem-tg"
  ip_address_type = "ipv4"
  port            = var.target_port
  protocol        = "HTTP"
  target_type     = "instance"
  vpc_id          = var.vpc_id

  health_check {
    path                = var.health_check_path
    protocol            = "HTTP"
    port                = var.target_port
    interval            = 60
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    enabled             = true
  }

  stickiness {
    type    = "lb_cookie"
    enabled = true
  }
}

resource "aws_lb_listener" "listener" {
  load_balancer_arn = aws_lb.application_load_balancer.arn
  port              = var.listener_port
  protocol          = "HTTP"

  default_action {
    target_group_arn = aws_lb_target_group.target_group.arn
    type             = "forward"
  }
}
