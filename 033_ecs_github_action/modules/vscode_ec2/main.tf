# Standalone rule resources rather than inline ingress/egress blocks (rules.md F-2), and the egress rule
# below is a fix rather than a transcription.
#
# The _monolithic template's group for this instance declared two ingress rules and no egress rule at all.
# In CloudFormation that leaves the allow-all egress AWS puts on a new group in place, because
# AWS::EC2::SecurityGroup only takes over the rules a template names. Terraform's inline ingress/egress are
# attributes-as-blocks and authoritative over the whole group, so declaring any of them revokes that
# default - and this instance does nothing but outbound work. dnf, the code-server tarball, the Docker Hub
# base image, the ECR token, the push, github.com and every SSM call go out from here. With egress revoked
# the apply still succeeds and the instance still reaches "running"; what fails is every association that
# follows, with a timeout rather than a reason.
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
resource "aws_vpc_security_group_ingress_rule" "ssh_from_anywhere" {
  count             = var.allow_inbound_from_anywhere ? 1 : 0
  security_group_id = aws_security_group.vscode_ec2_security_group.id
  description       = "SSH on the relocated port from anywhere"
  ip_protocol       = "tcp"
  from_port         = var.ssh_port
  to_port           = var.ssh_port
  cidr_ipv4         = "0.0.0.0/0"
}
resource "aws_iam_role" "vscode_ec2_iam_role" {
  name = var.iam_role_name
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
# without this module changing (rules.md B-7). toset is safe because the ARNs are literal strings in
# configuration and are therefore known at plan time (rules.md B-8).
resource "aws_iam_role_policy_attachment" "vscode_ec2_iam_role" {
  for_each   = toset(var.iam_policy_arns)
  role       = aws_iam_role.vscode_ec2_iam_role.name
  policy_arn = each.value
}
# An instance profile holds at most one role, so this attribute is a single role name string - not the list
# CloudFormation's AWS::IAM::InstanceProfile Roles property takes (rules.md A-3).
resource "aws_iam_instance_profile" "vscode_ec2_instance_profile" {
  role = aws_iam_role.vscode_ec2_iam_role.name
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
  # The script ends at the marker file, with no cfn-signal.
  #
  # The _monolithic template's last line was
  #
  #   /opt/aws/bin/cfn-signal -e $? --stack <stack> --resource BastionEc2 --region <region>
  #
  # which could not work for two independent reasons: there is no CloudFormation stack to signal, and
  # aws-cfn-bootstrap is not on Amazon Linux 2023, so the path does not exist and the line ends in "No such
  # file or directory". The CreationPolicy it was reporting to is not reproducible in Terraform either. The
  # marker file is what replaces both: it is written last, and every association in the root waits for it
  # before it starts (rules.md B-4/D-5).
  #
  # A drop-in file rather than the original's sed on "#Port 22". Amazon Linux 2023's sshd_config Includes
  # /etc/ssh/sshd_config.d/*.conf ahead of everything else, so a file there is unambiguous and survives a
  # package update replacing sshd_config - and a sed whose pattern stops matching fails silently, leaving
  # sshd on 22 with the security group open on a port nothing listens on.
  user_data                   = <<-EOT
    #!/bin/bash
    set -x
    dnf update -yq
    dnf install -yq git
    dnf groupinstall -yq "Development Tools"
    dnf install -yq python3.12 python3-pip
    ln -sf /usr/bin/python3.12 /usr/bin/python

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

    mkdir -p /etc/ssh/sshd_config.d
    cat > /etc/ssh/sshd_config.d/50-terraform-port.conf << 'TFSSHDPORT'
    Port ${var.ssh_port}
    TFSSHDPORT
    systemctl restart sshd
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
  # The role has to carry its managed policies before this instance boots, otherwise the first AWS call in
  # the bootstrap fails with AccessDenied and the script carries on to write its marker anyway. The
  # instance profile reference orders this after the profile and the role but not after the attachment
  # (rules.md D-1). The egress rule is listed for the same reason: cloud-init starts downloading within
  # seconds of launch.
  depends_on = [
    aws_iam_role_policy_attachment.vscode_ec2_iam_role,
    aws_vpc_security_group_egress_rule.all_outbound,
  ]
}
# An elastic IP, as the _monolithic template had it: the address in the README and the output stays the same
# across a stop and start of the instance, which an auto-assigned public IP does not.
resource "aws_eip" "vscode_elastic_ip" {
  count = var.create_elastic_ip ? 1 : 0
  tags = {
    Name = var.name
  }
}
resource "aws_eip_association" "vscode_elastic_ip_association" {
  count         = var.create_elastic_ip ? 1 : 0
  allocation_id = aws_eip.vscode_elastic_ip[0].allocation_id
  instance_id   = aws_instance.vscode_ec2.id
}
locals {
  # The elastic IP when there is one, the auto-assigned address otherwise.
  #
  # Reading it off the aws_eip resource rather than off the instance is deliberate. The _monolithic
  # template's output was "http://${aws_eip.bastion_elastic_ip.id}:8000", because the conversion mapped
  # CloudFormation's Ref on an AWS::EC2::EIP - which returns the address - onto .id, which is the allocation
  # ID. The URL it printed was http://eipalloc-0123...:8000, and nothing about that fails: the apply
  # succeeds and the output is a string that is not an address.
  #
  # The instance's own public_ip is not used either. It is read before aws_eip_association has run, so on a
  # first apply it reports the auto-assigned address rather than the elastic one.
  public_ip = var.create_elastic_ip ? aws_eip.vscode_elastic_ip[0].public_ip : aws_instance.vscode_ec2.public_ip
}
