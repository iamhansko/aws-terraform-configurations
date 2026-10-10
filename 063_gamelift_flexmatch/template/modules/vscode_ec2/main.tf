# Standalone rule resources rather than an inline dynamic "ingress" block (rules.md F-2), and the egress rule
# below is a fix rather than a transcription.
#
# The _monolithic template gave this group a dynamic "ingress" and no egress. In CloudFormation that keeps the
# allow-all egress AWS puts on every new group. In Terraform it does not, for two reasons that stack: the
# provider revokes that default egress rule on every aws_security_group it creates (resourceSecurityGroupCreate
# calls RevokeSecurityGroupEgress unconditionally), and inline ingress/egress blocks are authoritative over the
# whole group afterwards. Either way this instance came up with no outbound path at all - and it does nothing
# but outbound work: dnf, the code-server download, git clone from github.com, every S3 upload and the SSM agent
# itself. The apply still succeeded; what failed was every association after it, as a timeout.
resource "aws_security_group" "vscode_ec2_security_group" {
  name        = var.security_group_name
  description = var.security_group_description
  vpc_id      = var.vpc_id
  tags = {
    Name = var.security_group_name
  }
}
resource "aws_vpc_security_group_egress_rule" "all_outbound" {
  security_group_id = aws_security_group.vscode_ec2_security_group.id
  description       = "All outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
resource "aws_vpc_security_group_ingress_rule" "code_server_from_anywhere" {
  count             = var.allow_inbound_from_anywhere ? 1 : 0
  security_group_id = aws_security_group.vscode_ec2_security_group.id
  description       = "code-server from anywhere"
  ip_protocol       = "tcp"
  from_port         = var.code_server_port
  to_port           = var.code_server_port
  cidr_ipv4         = "0.0.0.0/0"
}
resource "aws_iam_role" "vscode_ec2_iam_role" {
  name_prefix = var.iam_role_name_prefix
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
# toset is safe because the ARNs are literal strings in configuration, known at plan time (rules.md B-7/B-8).
resource "aws_iam_role_policy_attachment" "vscode_ec2_iam_role" {
  for_each   = toset(var.iam_policy_arns)
  role       = aws_iam_role.vscode_ec2_iam_role.name
  policy_arn = each.value
}
# An instance profile holds at most one role, so this is a single role name string - not the list
# CloudFormation's AWS::IAM::InstanceProfile Roles property takes (rules.md A-3).
resource "aws_iam_instance_profile" "vscode_ec2_instance_profile" {
  name_prefix = var.iam_role_name_prefix
  role        = aws_iam_role.vscode_ec2_iam_role.name
}
resource "aws_instance" "vscode_ec2" {
  ami                  = var.ami_id
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
  # The script ends at the marker file, with no cfn-signal. The _monolithic template's last line was
  #
  #   /opt/aws/bin/cfn-signal -e $? --stack template --resource VsCodeEc2 --region <region>
  #
  # There is no CloudFormation stack to signal, and aws-cfn-bootstrap is not on Amazon Linux 2023, so that line
  # ended in "No such file or directory". The marker is what replaces it and the CreationPolicy it reported to:
  # it is written last, after additional_user_data, and the root's associations wait for it (rules.md B-4/D-5).
  user_data                   = <<-EOT
    #!/bin/bash
    set -x
    dnf update -yq
    dnf install -yq git

    export VSC_VERSION="${var.code_server_version}"
    wget -q https://github.com/coder/code-server/releases/download/v$VSC_VERSION/code-server-$VSC_VERSION-linux-amd64.tar.gz
    tar -xzf code-server-$VSC_VERSION-linux-amd64.tar.gz
    mv code-server-$VSC_VERSION-linux-amd64 /usr/local/lib/code-server
    ln -s /usr/local/lib/code-server/bin/code-server /usr/local/bin/code-server

    mkdir -p /home/ec2-user/.config/code-server
    cat > /home/ec2-user/.config/code-server/config.yaml << 'TFCODESERVERCONFIG'
    bind-addr: 0.0.0.0:${var.code_server_port}
    auth: none
    cert: false
    TFCODESERVERCONFIG
    chown -R ec2-user:ec2-user /home/ec2-user/.config

    cat > /etc/systemd/system/code-server.service << 'TFCODESERVERUNIT'
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
    TFCODESERVERUNIT
    systemctl daemon-reload
    systemctl enable --now code-server
    ${var.additional_user_data}
    %{if var.marker_file_path != null~}
    mkdir -p ${var.marker_file_path}
    touch ${var.marker_file_path}/userdata
    %{endif~}
    EOT
  subnet_id                   = var.subnet_id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.vscode_ec2_security_group.id]
  tags = {
    Name = var.name
  }
  # The role has to carry its policy before the bootstrap's first AWS call, and the egress rule has to exist
  # before cloud-init's first download seconds after launch. The instance profile reference orders this after
  # the role, not after the attachment or the rule (rules.md D-1).
  depends_on = [
    aws_iam_role_policy_attachment.vscode_ec2_iam_role,
    aws_vpc_security_group_egress_rule.all_outbound,
  ]
}
