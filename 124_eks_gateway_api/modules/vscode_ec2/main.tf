# The AMI the _monolithic template's AWS::SSM::Parameter::Value<AWS::EC2::Image::Id> parameter resolved.
#
# This data source stays inside the module because its result is used as a plain attribute. Nothing derives a
# for_each key or a count from it, so the module being ordered with depends_on by its caller - which defers
# every data source in it to apply - costs nothing here (rules.md D-6).
data "aws_ssm_parameter" "ami_id" {
  name = var.ami_ssm_parameter_name
}
resource "aws_security_group" "vscode_ec2_security_group" {
  description = var.security_group_description
  name        = var.security_group_name
  vpc_id      = var.vpc_id
  tags = {
    Name = var.security_group_name
  }
  # revoke_rules_on_delete is deliberately not set. It exists for groups a controller adds untracked rules to,
  # and nothing adds rules to this one: it is the workbench's own group, never named as a load balancer's
  # frontend group, and the AWS Load Balancer Controller writes its backend rules onto the group on the pod
  # ENIs instead - the EKS-managed cluster security group (rules.md F-2).
}
# Standalone rule resources rather than inline ingress/egress blocks on the group above.
#
# Nothing adds rules to this group today, so inline blocks would work - but that judgment is exactly what
# rules.md F-2 says not to make, because it flips later with one annotation and the way it flips is a
# controller's rule disappearing on the next apply with nothing said about it. New groups get standalone rules.
#
# toset over a list is safe for both of these: the values are literal CIDR strings from the configuration, so
# the for_each keys are known at plan time. A list of IDs coming out of another module would have to be a map
# instead (rules.md B-8).
resource "aws_vpc_security_group_ingress_rule" "code_server_from_anywhere" {
  count = var.allow_inbound_from_anywhere ? 1 : 0

  security_group_id = aws_security_group.vscode_ec2_security_group.id
  description       = "code-server from anywhere"
  ip_protocol       = "tcp"
  from_port         = var.code_server_port
  to_port           = var.code_server_port
  cidr_ipv4         = "0.0.0.0/0"
}
resource "aws_vpc_security_group_ingress_rule" "code_server_from_cidr_blocks" {
  for_each = toset(var.ingress_cidr_blocks)

  security_group_id = aws_security_group.vscode_ec2_security_group.id
  description       = "code-server from ${each.key}"
  ip_protocol       = "tcp"
  from_port         = var.code_server_port
  to_port           = var.code_server_port
  cidr_ipv4         = each.value
}
# The _monolithic template declared no egress rule at all, which in CloudFormation leaves the default
# allow-all in place. Terraform replaces the default with exactly what is declared, so omitting this would
# produce an instance that cannot download code-server, kubectl, helm, the CRD bundles or the chart.
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
# AWS::IAM::InstanceProfile Roles property accepts. The conversion carried the list over as
# jsonencode([...]), which is a valid string and an invalid role name - it passes validate and plan and fails
# in the IAM API during apply (rules.md A-3).
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
  # code-server only. Everything else the workbench needs arrives through additional_user_data, so this module
  # never learns whether its root has an EKS cluster in it (rules.md H-1).
  #
  # The version is a variable rather than the "curl the latest release from the GitHub API" the _monolithic
  # template used, which made the installed version a function of the day the stack was created - and failed
  # outright when the unauthenticated API rate limit was hit, because jq then parsed an error document and
  # VSC_VERSION came out empty.
  user_data                   = <<-EOT
    #!/bin/bash
    set -x
    dnf update -yq
    dnf install -yq git bind-utils
    dnf groupinstall -yq "Development Tools"
    export VSC_VERSION="${var.code_server_version}"
    wget -q https://github.com/coder/code-server/releases/download/v$VSC_VERSION/code-server-$VSC_VERSION-linux-amd64.tar.gz
    tar -xzf code-server-$VSC_VERSION-linux-amd64.tar.gz
    mv code-server-$VSC_VERSION-linux-amd64 /usr/local/lib/code-server
    ln -s /usr/local/lib/code-server/bin/code-server /usr/local/bin/code-server
    mkdir -p /home/ec2-user/.config/code-server
    cat <<EOF > /home/ec2-user/.config/code-server/config.yaml
    bind-addr: 0.0.0.0:${var.code_server_port}
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
  # Two things that have to be in place before this instance boots, and neither is implied by the references
  # above (rules.md D-1):
  #
  #   the policy attachments - otherwise the bootstrap script's AWS calls fail with AccessDenied;
  #   the egress rule - vpc_security_group_ids orders this after the group, not after the rules on it, and
  #     the group starts with no egress at all, so a boot that wins that race downloads nothing.
  depends_on = [
    aws_iam_role_policy_attachment.vscode_ec2_iam_role,
    aws_vpc_security_group_egress_rule.all_outbound,
  ]
}
