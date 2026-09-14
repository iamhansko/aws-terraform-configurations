data "aws_ssm_parameter" "ami_id" {
  name = var.ami_ssm_parameter_name
}

resource "aws_security_group" "auto_scaling_group_security_group" {
  description = "Security Group for AutoScalingGroup EC2"
  name        = "asg-sg"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [var.bastion_security_group_id]
  }

  ingress {
    from_port       = var.app_port
    to_port         = var.app_port
    protocol        = "tcp"
    security_groups = [var.bastion_security_group_id]
  }

  ingress {
    from_port       = var.app_port
    to_port         = var.app_port
    protocol        = "tcp"
    security_groups = [var.load_balancer_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "asg-sg"
  }
}

resource "aws_launch_template" "launch_template" {
  name          = "stem-template"
  image_id      = data.aws_ssm_parameter.ami_id.insecure_value
  instance_type = var.instance_type
  key_name      = var.key_name

  network_interfaces {
    device_index    = 0
    security_groups = [aws_security_group.auto_scaling_group_security_group.id]
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "stem-asg"
    }
  }

  user_data = base64encode(<<-EOT
    #!/bin/sh
    dnf install -yq httpd wget php-fpm php-mysqli php-json php php-devel
    dnf install -yq mariadb105-server
    dnf install -yq httpd php-mbstring
    chkconfig httpd on
    systemctl start httpd
    if [ ! -f /var/www/html/immersion-day-app-php7.zip ]; then
      cd /var/www/html
      wget -O 'immersion-day-app-php7.zip' '${var.sample_app_zip_url}'
      unzip immersion-day-app-php7.zip
    fi
    if [ ! -f /var/www/html/aws.zip ]; then
      cd /var/www/html
      mkdir vendor
      cd vendor
      wget ${var.aws_sdk_php_zip_url}
      unzip aws.zip
    fi
    dnf update -yq
    EOT
  )
}

resource "aws_autoscaling_group" "auto_scaling_group" {
  name                = "stem-asg"
  min_size            = var.min_size
  max_size            = var.max_size
  target_group_arns   = var.target_group_arns
  vpc_zone_identifier = var.subnet_ids

  launch_template {
    id      = aws_launch_template.launch_template.id
    version = aws_launch_template.launch_template.latest_version
  }
}

resource "aws_autoscaling_policy" "auto_scaling_policy" {
  name                   = "${var.prefix}-auto-scaling-policy"
  adjustment_type        = "PercentChangeInCapacity"
  autoscaling_group_name = aws_autoscaling_group.auto_scaling_group.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = var.target_cpu_utilization
  }
}
