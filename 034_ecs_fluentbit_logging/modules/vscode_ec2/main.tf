resource "aws_security_group" "vscode_ec2_security_group" {
  name        = var.security_group_name
  description = var.security_group_description
  vpc_id      = var.vpc_id
  tags = {
    Name = var.security_group_name
  }
}
# Standalone rule resources rather than inline ingress/egress blocks (rules.md F-2). The ingress rules
# below are a transcription of what the _monolithic template declared; the egress rule is a fix.
#
# That template's group named two ingress rules and no egress rule at all. In CloudFormation an
# AWS::EC2::SecurityGroup only takes over the rules the template actually names, so the allow-all egress
# rule AWS adds at creation stayed in place. Terraform's inline ingress/egress are attributes-as-blocks
# and authoritative over the whole group, so naming any rule and omitting egress does not inherit that
# default - the provider revokes it.
#
# On this instance that revocation is total. Every useful line of the bootstrap goes outbound: dnf,
# the code-server tarball from GitHub, the SSM agent's connection to the Systems Manager endpoints, and
# then the image build - the python base image from Docker Hub, the Fluent Bit image from public ECR, the
# ECR authorization token and both pushes. With egress gone, terraform apply still reports an instance
# that reached "running", code-server never answers on port 8000, and the SSM associations that drive the
# build fail with nothing more specific than "unexpected state 'Failed'".
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
# for_each over the CIDR list rather than one resource per source. The values are literals in
# configuration and so are known at plan time, which is what makes toset safe here (rules.md B-7/B-8).
resource "aws_vpc_security_group_ingress_rule" "ssh_ingress" {
  for_each = toset(var.ssh_ingress_cidr_blocks)

  security_group_id = aws_security_group.vscode_ec2_security_group.id
  description       = "SSH from ${each.value}"
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
  cidr_ipv4         = each.value
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
# One for_each attachment rather than one resource per policy, so a caller can add or remove a policy
# without this module changing (rules.md B-7).
resource "aws_iam_role_policy_attachment" "vscode_ec2_iam_role" {
  for_each   = toset(var.iam_policy_arns)
  role       = aws_iam_role.vscode_ec2_iam_role.name
  policy_arn = each.value
}
# aws_iam_instance_profile.role takes a single role name string, not the list CloudFormation's
# AWS::IAM::InstanceProfile Roles property accepts (rules.md A-3).
resource "aws_iam_instance_profile" "vscode_ec2_instance_profile" {
  role = aws_iam_role.vscode_ec2_iam_role.name
}
resource "aws_instance" "vscode_ec2" {
  ami                  = var.ami_id
  instance_type        = var.instance_type
  key_name             = var.key_name
  iam_instance_profile = aws_iam_instance_profile.vscode_ec2_instance_profile.name
  root_block_device {
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }
  # No cfn-signal at the end, which the _monolithic template's script finished with:
  #
  #   /opt/aws/bin/cfn-signal -e $? --stack <stack> --resource BastionEc2 --region <region>
  #
  # Two independent reasons it could never work here. There is no CloudFormation stack to signal, and
  # aws-cfn-bootstrap is not on Amazon Linux 2023 by default, so the path does not exist and the line
  # ends in "No such file or directory" - as the last line of the script, that also made the instance's
  # cloud-init exit status non-zero for no reason. The marker file below is the completion signal the
  # SSM associations in the root wait on instead (rules.md B-4/D-5).
  user_data                   = <<-EOT
    #!/bin/bash
    set -x
    dnf update -yq
    dnf groupinstall -yq "Development Tools"
    dnf install -yq git python3.12 python3-pip
    # -f rather than a bare ln: the symlink already exists on a re-run of this script and ln without it
    # fails, which puts a confusing error into cloud-init-output.log ahead of the real work.
    ln -sf /usr/bin/python3.12 /usr/bin/python
    export VSC_VERSION="${var.code_server_version}"
    wget -q https://github.com/coder/code-server/releases/download/v$VSC_VERSION/code-server-$VSC_VERSION-linux-amd64.tar.gz
    tar -xzf code-server-$VSC_VERSION-linux-amd64.tar.gz
    mv code-server-$VSC_VERSION-linux-amd64 /usr/local/lib/code-server
    ln -sf /usr/local/lib/code-server/bin/code-server /usr/local/bin/code-server
    mkdir -p /home/ec2-user/.config/code-server
    cat > /home/ec2-user/.config/code-server/config.yaml << 'TFCODESERVER'
    bind-addr: 0.0.0.0:${var.code_server_port}
    auth: none
    cert: false
    TFCODESERVER
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
  associate_public_ip_address = var.associate_public_ip_address
  vpc_security_group_ids      = concat([aws_security_group.vscode_ec2_security_group.id], var.extra_security_group_ids)
  tags = {
    Name = var.name
  }
  # The role must already carry its managed policies before this instance boots, otherwise the bootstrap
  # script's AWS calls fail with AccessDenied (rules.md D-1). The egress rule is listed for the same
  # reason: cloud-init starts downloading within seconds of launch.
  depends_on = [
    aws_iam_role_policy_attachment.vscode_ec2_iam_role,
    aws_vpc_security_group_egress_rule.all_outbound,
  ]
}
resource "aws_eip" "vscode_ec2_elastic_ip" {
  domain = "vpc"
  tags = {
    Name = var.name
  }
}
# A separate association rather than the instance's own launch-time public IP, as the _monolithic template
# had it. The address then survives a stop and start of the instance, which matters because the URL in the
# root's outputs and in the README written onto the instance are both built from this one.
resource "aws_eip_association" "vscode_ec2_elastic_ip_association" {
  allocation_id = aws_eip.vscode_ec2_elastic_ip.allocation_id
  instance_id   = aws_instance.vscode_ec2.id
}
