resource "aws_security_group" "vscode_ec2_security_group" {
  name        = var.security_group_name
  description = var.security_group_description
  vpc_id      = var.vpc_id
  tags = {
    Name = var.security_group_name
  }
}
# Standalone rule resources rather than inline ingress and egress blocks (rules.md F-2), and here that
# is not a style preference - the inline form would have silently broken this instance.
#
# The _monolithic template declared two inline ingress blocks, for 22 and 8000, and no egress block.
# CloudFormation's AWS::EC2::SecurityGroup leaves the allow-all egress rule that EC2 attaches to every
# new group in place when a template names only SecurityGroupIngress, so the source template never had
# to spell outbound access out. Terraform's inline blocks are attributes-as-blocks and authoritative
# over the whole group: omitting egress does not inherit that default, it revokes it.
#
# The result would be an instance with no outbound access at all, and apply would report success
# throughout. code-server is downloaded from github.com in user data, so it would never install and
# port 8000 would refuse every connection - and the SSM agent could not reach its endpoints either, so
# the instance would also be unreachable through Session Manager, which is where anyone would go to
# find out why. The README association in the caller would then fail with "unexpected state 'Failed'"
# naming nothing useful.
#
# This is not hypothetical. The same omission broke 101_ubuntu_xrdp, where cloud-init could not reach
# the package repositories, and was caught twice more in 103_ecs_volumes. Standalone rules make each
# direction a resource that is visibly present or visibly absent in a plan.
locals {
  # Port per purpose, built from the two port variables rather than taken as a map, so the code-server
  # port has exactly one definition - it is also written into the config file the bootstrap generates
  # and into the URL in the outputs (rules.md B-5).
  ingress_ports = {
    ssh         = var.ssh_port
    code_server = var.code_server_port
  }
  # One rule per (port, source) pair. Both halves are literals in configuration, so the keys are known
  # at plan time, which is what for_each needs; rules.md B-8 only forces the map-with-static-keys form
  # when the values are another module's output.
  ingress_rules = {
    for pair in flatten([
      for purpose, port in local.ingress_ports : [
        for cidr in var.ingress_cidr_blocks : {
          key     = "${purpose}-${cidr}"
          purpose = purpose
          port    = port
          cidr    = cidr
        }
      ]
    ]) : pair.key => pair
  }
}
resource "aws_vpc_security_group_ingress_rule" "vscode_ec2_ingress" {
  for_each = local.ingress_rules

  security_group_id = aws_security_group.vscode_ec2_security_group.id
  # each.key in the description so a plan says which rule is which. No apostrophe anywhere in it: the
  # charset limit on a security group description applies to rule descriptions too, and a rule is
  # rejected at apply rather than at plan (rules.md F-1).
  description = "Port ${each.value.port} (${each.value.purpose}) from ${each.value.cidr}"
  ip_protocol = "tcp"
  from_port   = each.value.port
  to_port     = each.value.port
  cidr_ipv4   = each.value.cidr
}
# The rule the _monolithic template got for free from CloudFormation and that Terraform's inline form
# would have taken away. Everything the bootstrap does needs it: dnf, the code-server download from
# GitHub, and the SSM agent's connection to its own endpoints.
resource "aws_vpc_security_group_egress_rule" "vscode_ec2_egress" {
  security_group_id = aws_security_group.vscode_ec2_security_group.id
  description       = "All outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
resource "aws_iam_role" "vscode_ec2_iam_role" {
  name_prefix = var.role_name_prefix
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = ["ec2.amazonaws.com"] }
      Action    = ["sts:AssumeRole"]
    }]
  })
}
# for_each over the policy list rather than one attachment resource per policy, which is what the
# _monolithic template had - bastion_ec2_role_0 and bastion_ec2_role_1, differing only in the ARN
# (rules.md B-7). toset is safe because the ARNs are literals in configuration and so are known at
# plan time (rules.md B-8).
resource "aws_iam_role_policy_attachment" "vscode_ec2_iam_role" {
  for_each   = toset(var.iam_policy_arns)
  role       = aws_iam_role.vscode_ec2_iam_role.name
  policy_arn = each.value
}
resource "aws_iam_instance_profile" "vscode_ec2_instance_profile" {
  name_prefix = var.role_name_prefix
  # A single role name string, not the list CloudFormation's AWS::IAM::InstanceProfile Roles property
  # takes (rules.md A-3). This is the third instance profile in this project, and the one the Config
  # rule is taught to skip by Name tag - if it were built wrong the rule would never report it, so the
  # mistake would surface only as the instance launching without credentials.
  role = aws_iam_role.vscode_ec2_iam_role.name
}
locals {
  # The bootstrap, as the _monolithic template's user data had it, with two changes.
  #
  # set -x is added, so every command lands in /var/log/cloud-init-output.log - that file is what the
  # bootstrap_log_command output points at and the only place a half-finished bootstrap explains
  # itself. Nothing here handles a secret, so there is nothing to leak into it.
  #
  # The cfn-signal call at the end is dropped. It read
  # "/opt/aws/bin/cfn-signal -e $? --stack <name> --resource BastionEc2", which existed to satisfy the
  # CreationPolicy that CloudFormation was waiting on. The conversion already notes that the
  # CreationPolicy has no Terraform equivalent and is not reproduced, so the signal had nothing to
  # signal - and aws-cfn-bootstrap is not installed on Amazon Linux 2023, so the line failed with "No
  # such file or directory" on every boot. The marker file at the bottom is what replaces it: it is
  # read by an until loop rather than by a service (rules.md D-5).
  user_data = <<-EOT
    #!/bin/bash
    set -x
    dnf update -yq
    dnf groupinstall -yq "Development Tools"
    dnf install -yq python${var.python_version} python3-pip git
    ln -sf /usr/bin/python${var.python_version} /usr/bin/python

    # The version appears three times in the next four lines, which is why it is a variable: the
    # _monolithic template repeated the literal in all three, so a bump made in only the URL left the
    # mv looking for a directory that did not exist.
    export VSC_VERSION="${var.code_server_version}"
    wget -q https://github.com/coder/code-server/releases/download/v$VSC_VERSION/code-server-$VSC_VERSION-linux-amd64.tar.gz
    tar -xzf code-server-$VSC_VERSION-linux-amd64.tar.gz
    mv code-server-$VSC_VERSION-linux-amd64 /usr/local/lib/code-server
    ln -sf /usr/local/lib/code-server/bin/code-server /usr/local/bin/code-server

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
    # The marker is the last thing the script does, after additional_user_data rather than before it.
    # Touching it earlier would release an association that is waiting on it while the caller's extra
    # setup is still running (rules.md B-4, H-2).
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
  vpc_security_group_ids      = concat([aws_security_group.vscode_ec2_security_group.id], var.extra_security_group_ids)
  iam_instance_profile        = aws_iam_instance_profile.vscode_ec2_instance_profile.name
  user_data                   = local.user_data
  # Not in the _monolithic template, which left IMDSv1 available. Nothing in the bootstrap reads
  # instance metadata, so requiring tokens costs nothing here and closes the path that turns an SSRF
  # in anything running on this instance into the credentials of a role holding AdministratorAccess.
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }
  tags = {
    Name = var.name
  }

  # iam_instance_profile orders this after the profile and the role, but after neither attachment -
  # nothing in this resource refers to them. They have to be in place before the instance boots: the
  # SSM agent registers using this role, so without them the agent cannot register, the README
  # association has no target to run on and fails with "unexpected state 'Failed'" (rules.md D-1).
  depends_on = [aws_iam_role_policy_attachment.vscode_ec2_iam_role]
}
