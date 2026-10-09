resource "aws_security_group" "vscode_ec2_security_group" {
  name        = var.security_group_name
  description = var.security_group_description
  vpc_id      = var.vpc_id
  tags = {
    Name = var.security_group_name
  }
}
# Standalone rule resources rather than inline ingress/egress blocks (rules.md F-2), and the egress rule is
# a fix rather than a transcription.
#
# The _monolithic template declared this group with two inline ingress blocks - SSH and code-server - and no
# egress block. CloudFormation's AWS::EC2::SecurityGroup leaves the allow-all egress rule EC2 attaches to a
# new group alone when a template names only ingress, so the source never had to spell outbound out.
# Terraform's inline blocks are attributes-as-blocks and authoritative over the whole group: omitting egress
# does not inherit that default, it revokes it.
#
# For this instance that is total. Every useful line of the bootstrap goes outbound - dnf update, the
# Development Tools group, the code-server tarball from GitHub, the docker package, the python base image
# from Docker Hub, the ECR authorization token and the push. With egress revoked the instance reaches
# "running", the apply reports success, and the only evidence is wget and dnf timing out in
# /var/log/cloud-init-output.log. Downstream it surfaces minutes later as an ECS service reporting
# CannotPullContainerError against an image that was never built, and nothing in that chain points back
# here.
resource "aws_vpc_security_group_ingress_rule" "code_server_ingress" {
  for_each = toset(var.ingress_cidr_blocks)

  security_group_id = aws_security_group.vscode_ec2_security_group.id
  description       = "code-server from ${each.value}"
  ip_protocol       = "tcp"
  from_port         = var.code_server_port
  to_port           = var.code_server_port
  cidr_ipv4         = each.value
}
resource "aws_vpc_security_group_ingress_rule" "ssh_ingress" {
  for_each = toset(var.ingress_cidr_blocks)

  security_group_id = aws_security_group.vscode_ec2_security_group.id
  description       = "SSH from ${each.value}"
  ip_protocol       = "tcp"
  from_port         = var.ssh_port
  to_port           = var.ssh_port
  cidr_ipv4         = each.value
}
resource "aws_vpc_security_group_egress_rule" "all_outbound" {
  security_group_id = aws_security_group.vscode_ec2_security_group.id
  description       = "All outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
resource "aws_iam_role" "vscode_ec2_iam_role" {
  name_prefix = var.iam_name_prefix
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
# for_each over the policy list rather than one attachment resource per policy, so a caller can add or
# remove a policy without this module changing (rules.md B-7). toset is safe because the ARNs are literal
# strings in configuration and so are known at plan time (rules.md B-8).
resource "aws_iam_role_policy_attachment" "vscode_ec2_iam_role" {
  for_each   = toset(var.iam_policy_arns)
  role       = aws_iam_role.vscode_ec2_iam_role.name
  policy_arn = each.value
}
resource "aws_iam_instance_profile" "vscode_ec2_instance_profile" {
  name_prefix = var.iam_name_prefix
  # An instance profile holds at most one role, so this attribute is a single role name string - not the
  # list CloudFormation's AWS::IAM::InstanceProfile Roles property takes. jsonencode([...]) here would send
  # the literal string ["Ec2AdminProfile-..."] as roleName, which IAM rejects during apply while terraform
  # validate and plan both pass, because the attribute is a string either way (rules.md A-3). The conversion
  # got this one right; the trap is noted because the next person editing this block is the one who would
  # reintroduce it.
  role = aws_iam_role.vscode_ec2_iam_role.name
}
locals {
  # rules.md H-1's five-tool list does not apply to this root: it is conditional on the root also declaring
  # an EKS cluster, and there is none here - this is ECS on Fargate. So no kubectl, eksctl or helm, which
  # would be three downloads nothing in this project uses. code-server is installed here; docker is what
  # this project's demo needs and arrives through additional_user_data, so this module does not have to know
  # what is being built on it (rules.md B-4).
  user_data = <<-EOT
    #!/bin/bash
    set -x
    dnf update -yq
    dnf groupinstall -yq "Development Tools"
    dnf install -yq git python${var.python_version} python3-pip
    # -sf rather than the original's bare -s. /usr/bin/python may already exist, and ln without -f then
    # fails with "File exists" - which under set -x is one red line in a log nobody reads, leaving every
    # later "python" invocation on the box pointing somewhere unintended.
    ln -sf /usr/bin/python${var.python_version} /usr/bin/python

    export VSC_VERSION="${var.code_server_version}"
    wget -q https://github.com/coder/code-server/releases/download/v$VSC_VERSION/code-server-$VSC_VERSION-linux-amd64.tar.gz
    tar -xzf code-server-$VSC_VERSION-linux-amd64.tar.gz
    mv code-server-$VSC_VERSION-linux-amd64 /usr/local/lib/code-server
    ln -sf /usr/local/lib/code-server/bin/code-server /usr/local/bin/code-server

    mkdir -p /home/ec2-user/.config/code-server
    cat <<'TFCODESERVERCONFIG' > /home/ec2-user/.config/code-server/config.yaml
    bind-addr: 0.0.0.0:${var.code_server_port}
    auth: none
    cert: false
    TFCODESERVERCONFIG
    chown -R ec2-user:ec2-user /home/ec2-user/.config

    cat <<'TFCODESERVERUNIT' > /etc/systemd/system/code-server.service
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
    # The marker goes last, after additional_user_data (rules.md B-4). It replaces the
    # "/opt/aws/bin/cfn-signal -e $? --stack ... --resource BastionEc2" the original ended on, which could
    # never have worked for two independent reasons: there is no CloudFormation stack to signal, and
    # aws-cfn-bootstrap is not installed on Amazon Linux 2023, so that path does not exist and the line
    # ends in "No such file or directory".
    #
    # Touching it any earlier would release the associations the root chains off it while docker is still
    # installing and the image has not been built, and one of those associations is the one that decides
    # whether the image exists (rules.md D-5/H-2).
    %{if var.marker_file_path != null~}
    mkdir -p ${var.marker_file_path}
    touch ${var.marker_file_path}/userdata
    %{endif~}
    EOT
}
resource "aws_instance" "vscode_ec2" {
  ami                         = var.ami_id
  instance_type               = var.instance_type
  key_name                    = var.key_name
  subnet_id                   = var.subnet_id
  associate_public_ip_address = var.associate_public_ip_address
  iam_instance_profile        = aws_iam_instance_profile.vscode_ec2_instance_profile.name
  vpc_security_group_ids      = concat([aws_security_group.vscode_ec2_security_group.id], var.extra_security_group_ids)
  user_data                   = local.user_data
  tags = {
    Name = var.instance_name
  }
  root_block_device {
    # Larger than the AL2023 default of 8 GiB the _monolithic template took. This instance installs the
    # Development Tools group and then builds a container image, and docker keeps every intermediate layer
    # in its cache on the same disk.
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  # The role must already carry its managed policy before this instance boots. The instance profile
  # reference orders this after the profile and the role but not after the attachment - nothing here refers
  # to it - and the bootstrap's first AWS call is "aws ecr get-login-password", seconds after launch. Losing
  # that race gives an AccessDenied on the token and the script carries on to the marker anyway
  # (rules.md D-1). The egress rule is listed for the same reason: cloud-init starts downloading
  # immediately.
  depends_on = [
    aws_iam_role_policy_attachment.vscode_ec2_iam_role,
    aws_vpc_security_group_egress_rule.all_outbound,
  ]
}
