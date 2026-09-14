resource "aws_security_group" "network_load_balancer_security_group" {
  description = "Security Group for Network Load Balancer"
  name        = "nlb-sg"
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
    Name = "nlb-sg"
  }
}

resource "aws_lb" "network_load_balancer" {
  name               = "stem-nlb"
  ip_address_type    = "ipv4"
  load_balancer_type = "network"
  internal           = false
  security_groups    = [aws_security_group.network_load_balancer_security_group.id]
  subnets            = var.subnet_ids
}

resource "aws_lb_target_group" "target_group" {
  name            = "stem-tg"
  ip_address_type = "ipv4"
  port            = var.target_port
  protocol        = "TCP"
  target_type     = "instance"
  vpc_id          = var.vpc_id

  health_check {
    protocol            = "TCP"
    interval            = 60
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    enabled             = true
  }
}

resource "aws_lb_listener" "listener" {
  load_balancer_arn = aws_lb.network_load_balancer.arn
  port              = var.listener_port
  protocol          = "TCP"

  default_action {
    target_group_arn = aws_lb_target_group.target_group.arn
    type             = "forward"
  }
}
