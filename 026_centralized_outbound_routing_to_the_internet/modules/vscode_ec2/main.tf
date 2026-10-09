# The one instance in this project, and the thing whose traffic the whole topology exists to carry.
#
# The _monolithic template called it app-bastion and gave it a four-line userdata: dnf update, dnf
# install bind-utils, then cfn-signal. Nothing connected through it - no key pair in a reachable
# place, no inbound rule, no public address - so "bastion" was already the wrong word; what it was is
# a host inside the app VPC from which to prove that egress works and that the firewall's rules bite.
# dig, from bind-utils, was the whole toolkit.
#
# It is a vscode_ec2 here, meaning code-server is installed on top of that. Two consequences worth
# being explicit about, because they are divergences from the original:
#
#   - The root now declares module "vscode_ec2", which makes rules.md H-2 apply: every root output is
#     defined once in a local.outputs map and rendered onto this host as /home/ec2-user/README.md.
#     That is most of the value of the change - the probes this project turns on are shell commands,
#     and the place to run them is here, where "terraform output" does not exist.
#   - rules.md H-1 does not apply. It covers a root declaring both an EKS cluster and a vscode_ec2,
#     and there is no cluster anywhere in this project, so kubectl, eksctl and helm are not installed
#     and should not be. bind-utils and the AWS CLI are the tools this demo needs.
#
# code-server is not reachable from the internet and cannot be made so: this subnet is in a VPC with
# no internet gateway. It is reached by forwarding the port over SSM Session Manager, which is the
# command in the root's outputs.
data "aws_ssm_parameter" "ami_id" {
  name = var.ami_ssm_parameter_name
}
resource "aws_security_group" "vscode_ec2" {
  name        = var.security_group_name
  description = var.security_group_description
  vpc_id      = var.vpc_id
  tags = {
    Name = var.security_group_name
  }
  # revoke_rules_on_delete deliberately unset. It is for groups a controller adds untracked rules to,
  # and nothing adds rules to this one - there is no load balancer controller and no AWS service with
  # a reason to touch it (rules.md F-2).
}
# Standalone rule resources rather than inline ingress/egress blocks, and in this project that choice
# is the difference between a demo and a demo-shaped thing that proves nothing (rules.md F-2).
#
# The _monolithic template declared no security group at all. Its instance took
# aws_vpc.app_vpc.default_security_group_id - the VPC's default group, which allows all traffic from
# itself and all traffic outbound, and whose contents are whatever else has been done to that account
# over time. Replacing it with a named group is right, and it arms a trap: EC2 attaches an allow-all
# egress rule to every group it creates, the provider revokes that rule as soon as it manages the
# group, and inline ingress/egress blocks are attributes-as-blocks - authoritative over the whole
# group. So declaring only the ingress side does not leave egress alone, it removes it.
#
# Here that failure would be unusually hard to read. Nothing about the apply fails. The instance
# launches into a private subnet, boots, and cannot reach anything: dnf update hangs, code-server is
# never downloaded, the marker file is never touched, and the aws_ssm_association that renders the
# README waits until readme_timeout_seconds and then fails with "unexpected state 'Failed'" - which
# names the association, not the missing rule, and arrives after a transit gateway, two NAT gateways
# and a Network Firewall have all been created. And the thing being demonstrated is centralized
# egress, so an instance with no egress makes every probe in the outputs return the same answer a
# correctly built but misrouted project would: nothing works, for an unrelated reason.
#
# The rule below is therefore explicit, and its absence would show up in a plan as a missing resource
# rather than as a boot that quietly goes nowhere.
resource "aws_vpc_security_group_egress_rule" "all_outbound" {
  security_group_id = aws_security_group.vscode_ec2.id
  description       = "All outbound - this is the traffic the transit gateway and the egress VPC exist to carry"
  ip_protocol       = "-1"
  cidr_ipv4         = var.egress_cidr_ipv4
}
# Normally none, and none is the correct state: the app VPC has no internet gateway, so no rule
# written here can admit a connection from outside it however permissive it is. An address inside
# either VPC does work, which is what this is kept for (rules.md B-4).
#
# toset over a list is safe because these are literal CIDR strings from configuration, so the
# for_each keys are known during plan. A list of security group IDs from another module would have to
# arrive as a map instead (rules.md B-8).
resource "aws_vpc_security_group_ingress_rule" "code_server" {
  for_each = toset(var.ingress_cidr_blocks)

  security_group_id = aws_security_group.vscode_ec2.id
  description       = "code-server from ${each.value}"
  ip_protocol       = "tcp"
  from_port         = var.code_server_port
  to_port           = var.code_server_port
  cidr_ipv4         = each.value
}
resource "aws_iam_role" "vscode_ec2" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = ["ec2.amazonaws.com"]
      }
      Action = "sts:AssumeRole"
    }]
  })
}
# One attachment resource over the policy list, rather than the _monolithic file's two numbered
# copies - bastion_ec2_iam_role_0 and bastion_ec2_iam_role_1, which is what the conversion produces
# from a CloudFormation ManagedPolicyArns list (rules.md B-7). toset is safe for the same reason as
# on the ingress rule above: these ARNs are configuration literals (rules.md B-8).
resource "aws_iam_role_policy_attachment" "vscode_ec2" {
  for_each   = toset(var.iam_policy_arns)
  role       = aws_iam_role.vscode_ec2.name
  policy_arn = each.value
}
resource "aws_iam_instance_profile" "vscode_ec2" {
  # An instance profile holds at most one role, so this attribute is a single role name string - not
  # the list CloudFormation's AWS::IAM::InstanceProfile Roles property takes. A conversion that
  # carries the list over as jsonencode([...]) produces a valid string and an invalid role name: it
  # passes terraform validate and terraform plan, because the attribute is a string either way, and
  # fails in the IAM API during apply (rules.md A-3).
  #
  # The _monolithic file is already correct here and carries the same note - the conversion was
  # evidently hand-fixed. Repeated because the fix is invisible: there is nothing in the corrected
  # line to stop someone "restoring" the list.
  role = aws_iam_role.vscode_ec2.name
}
locals {
  package_install = "dnf install -yq ${join(" ", var.dnf_packages)}"
  # No cfn-signal. The _monolithic template's script ended with
  # "/opt/aws/bin/cfn-signal -e $? --stack <name> --resource BastionEc2 --region <region>", which
  # could not work for two independent reasons: Amazon Linux 2023 does not ship aws-cfn-bootstrap, so
  # that path does not exist and the line fails with "No such file or directory"; and there is no
  # CloudFormation stack to signal, which the conversion itself records in the note where it dropped
  # the CreationPolicy. The marker file below is what replaces the wait it was signalling for, and it
  # is read by the SSM association in the root rather than by CloudFormation (rules.md D-5/H-2).
  user_data = <<-EOT
    #!/bin/bash
    set -x
    dnf update -yq
    ${local.package_install}
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
}
resource "aws_instance" "vscode_ec2" {
  ami                         = data.aws_ssm_parameter.ami_id.insecure_value
  instance_type               = var.instance_type
  key_name                    = var.key_name
  subnet_id                   = var.subnet_id
  associate_public_ip_address = var.associate_public_ip_address
  vpc_security_group_ids      = concat([aws_security_group.vscode_ec2.id], var.extra_security_group_ids)
  iam_instance_profile        = aws_iam_instance_profile.vscode_ec2.name
  user_data                   = local.user_data
  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
    encrypted   = true
  }
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = var.metadata_http_tokens
    http_put_response_hop_limit = var.metadata_hop_limit
  }
  tags = {
    Name = var.name
  }
  # Two preconditions for this boot, neither implied by the arguments above (rules.md D-1):
  #
  #   The policy attachments. iam_instance_profile orders this after the profile and the role, not
  #     after the policies on the role, and the bootstrap starts making AWS calls within a minute of
  #     launch - including the SSM agent's registration, which is what the README association needs.
  #     A policy that lands later gives AccessDenied on a role that will be correct shortly
  #     afterwards, and nothing retries the parts of the script that already ran.
  #   The egress rule. vpc_security_group_ids orders this after the group, not after the rules on it,
  #     and a group with no egress rule yet lets nothing out - so a boot that wins that race fails
  #     every download in the script. See the long note on that resource.
  #
  # Not listed, and the reason the module block in the root carries depends_on instead: this instance
  # also needs the entire egress path - the app VPC's route to the transit gateway, the gateway's
  # default route, the attachment subnets' routes to the NAT gateways and the public route table's
  # route to the internet gateway. None of those are in this module, and none of them are referenced
  # by any argument here, so the root is where they are named (rules.md D-2).
  depends_on = [
    aws_iam_role_policy_attachment.vscode_ec2,
    aws_vpc_security_group_egress_rule.all_outbound,
  ]
}
