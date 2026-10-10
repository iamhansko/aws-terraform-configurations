data "aws_ssm_parameter" "ami_id" {
  name = var.ami_ssm_parameter_name
}
locals {
  # With a path prefix, nginx answers on 80 and proxies <prefix>/ to code-server, which then binds to loopback
  # only - so the security group opens 80, to the ingress prefix lists and nothing else, and code-server's own
  # port is reachable from nowhere but nginx. Without one, code-server answers on its own port directly, as
  # the other projects' workbenches do.
  behind_nginx  = var.path_prefix != null
  listen_port   = local.behind_nginx ? 80 : var.code_server_port
  bind_address  = local.behind_nginx ? "127.0.0.1" : "0.0.0.0"
  nginx_install = <<-EOT
    dnf install -yq nginx
    # Single quotes, so nginx's own variables reach the file. The _monolithic default variant wrote this
    # config with echo "...", which made the shell expand $is_args, $args, $http_host and $http_upgrade to
    # nothing: nginx then refused "proxy_set_header Host ;" and never started, so the EC2 origin answered
    # nothing at all. The Lambda@Edge project's copy used single quotes and was correct.
    cat > /etc/nginx/conf.d/code-server.conf << 'NGINXCONF'
    server {
      location = ${var.path_prefix} {
        return 302 ${var.path_prefix}/$is_args$args;
      }
      location ${var.path_prefix}/ {
        proxy_pass http://127.0.0.1:${var.code_server_port}/;
        proxy_set_header Host $http_host;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection upgrade;
        proxy_set_header Accept-Encoding gzip;
      }
    }
    NGINXCONF
    nginx -t
    systemctl enable --now nginx
  EOT
}
# Standalone rule resources rather than inline ingress/egress blocks (rules.md F-2).
resource "aws_security_group" "vscode_ec2_security_group" {
  description = "Security Group for the VS Code EC2 instance"
  name        = var.security_group_name
  vpc_id      = var.vpc_id
  tags = {
    Name = var.security_group_name
  }
}
# The group's only inbound rule. code-server runs with auth: none, so its port admits nothing but the managed
# prefix lists the caller passes - for a CloudFront origin, the origin-facing list CloudFront connects from.
# There is no 0.0.0.0/0 rule and no switch to add one; the instance is reached through the distribution, or
# through SSM.
resource "aws_vpc_security_group_ingress_rule" "listen_port_from_prefix_list" {
  for_each          = toset(var.ingress_prefix_list_ids)
  security_group_id = aws_security_group.vscode_ec2_security_group.id
  description       = "code-server from a supplied managed prefix list"
  ip_protocol       = "tcp"
  from_port         = local.listen_port
  to_port           = local.listen_port
  prefix_list_id    = each.value
}
# Stated explicitly. The _monolithic template's group had no egress rule, and Terraform - unlike
# CloudFormation - removes the allow-all egress rule AWS puts on a new group, so that instance could not
# download code-server, nginx or reach SSM.
resource "aws_vpc_security_group_egress_rule" "all_outbound" {
  security_group_id = aws_security_group.vscode_ec2_security_group.id
  description       = "All outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
resource "aws_iam_role" "vscode_ec2_iam_role" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = ["ec2.amazonaws.com"]
      }
      Action = ["sts:AssumeRole"]
    }]
  })
}
resource "aws_iam_role_policy_attachment" "vscode_ec2_iam_role" {
  for_each   = toset(var.iam_policy_arns)
  role       = aws_iam_role.vscode_ec2_iam_role.name
  policy_arn = each.value
}
# aws_iam_instance_profile.role takes a single role name, not the list that CloudFormation's
# AWS::IAM::InstanceProfile Roles property accepts (rules.md A-3).
resource "aws_iam_instance_profile" "vscode_ec2_instance_profile" {
  role = aws_iam_role.vscode_ec2_iam_role.name
}
resource "aws_instance" "vscode_ec2" {
  ami                  = data.aws_ssm_parameter.ami_id.insecure_value
  instance_type        = var.instance_type
  key_name             = var.key_name
  iam_instance_profile = aws_iam_instance_profile.vscode_ec2_instance_profile.name
  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
    encrypted   = true
  }
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }
  # No cfn-signal at the end, which the _monolithic template's script carried. There is no CloudFormation
  # stack to signal and aws-cfn-bootstrap is not installed on Amazon Linux 2023. The completion marker below
  # is what replaces it (rules.md B-4/D-5).
  user_data                   = <<-EOT
    #!/bin/bash
    set -x
    dnf update -yq
    dnf install -yq git
    dnf groupinstall -yq "Development Tools"
    export VSC_VERSION="${var.code_server_version}"
    wget -q https://github.com/coder/code-server/releases/download/v$VSC_VERSION/code-server-$VSC_VERSION-linux-amd64.tar.gz
    tar -xzf code-server-$VSC_VERSION-linux-amd64.tar.gz
    mv code-server-$VSC_VERSION-linux-amd64 /usr/local/lib/code-server
    ln -s /usr/local/lib/code-server/bin/code-server /usr/local/bin/code-server
    mkdir -p /home/ec2-user/.config/code-server
    cat <<EOF > /home/ec2-user/.config/code-server/config.yaml
    bind-addr: ${local.bind_address}:${var.code_server_port}
    auth: none
    cert: false
    EOF
    chown -R ec2-user:ec2-user /home/ec2-user/.config
    cat <<EOF > /etc/systemd/system/code-server.service
    [Unit]
    Description=VS Code Server
    After=network.target
    [Service]
    Type=simple
    User=ec2-user
    ExecStart=/usr/local/bin/code-server --config /home/ec2-user/.config/code-server/config.yaml /home/ec2-user
    Restart=always
    [Install]
    WantedBy=multi-user.target
    EOF
    systemctl daemon-reload
    systemctl enable --now code-server
    %{if local.behind_nginx~}
    ${local.nginx_install}
    %{endif~}
    ${var.additional_user_data}
    %{if var.marker_file_path != null~}
    mkdir -p ${var.marker_file_path}
    touch ${var.marker_file_path}/userdata
    %{endif~}
    EOT
  subnet_id                   = var.subnet_id
  associate_public_ip_address = var.associate_public_ip_address
  vpc_security_group_ids      = concat([aws_security_group.vscode_ec2_security_group.id], var.extra_security_group_ids)
  tags = {
    Name = var.name
  }
  # The instance profile's role must already carry its managed policies before the instance boots, otherwise
  # the bootstrap script's AWS calls fail with AccessDenied (rules.md D-1). The egress rule is listed for the
  # same reason: cloud-init starts downloading within seconds of launch.
  depends_on = [
    aws_iam_role_policy_attachment.vscode_ec2_iam_role,
    aws_vpc_security_group_egress_rule.all_outbound,
  ]
}
