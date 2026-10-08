resource "aws_security_group" "ubuntu_ec2_security_group" {
  name        = var.security_group_name
  description = var.security_group_description
  vpc_id      = var.vpc_id
  tags = {
    Name = var.security_group_name
  }
}
# Standalone rule resources rather than inline ingress/egress blocks (rules.md
# F-2). Nothing adds rules to this group behind Terraform's back - there is no
# load balancer controller here - so the usual reason does not apply, but the
# reason this project specifically does not use inline blocks does.
#
# The _monolithic template declared a single inline ingress block for 3389 and
# no egress block. CloudFormation's AWS::EC2::SecurityGroup leaves the default
# allow-all egress rule alone when a template names only SecurityGroupIngress,
# so the source template never had to spell egress out. Terraform's inline
# blocks are attributes-as-blocks and authoritative over the whole group, so
# omitting egress does not inherit that default, it revokes it - the group ends
# up with no outbound access at all.
#
# That broke the project rather than warning about it. apply reported success,
# the instance came up, and cloud-init could not reach archive.ubuntu.com, so
# xrdp was never installed and port 3389 refused every connection. Standalone
# rules make each direction a resource that is visibly there or visibly absent
# in a plan, which is the shape that would have made this obvious.
resource "aws_vpc_security_group_ingress_rule" "ubuntu_ec2_rdp_ingress" {
  for_each = toset(var.ingress_cidr_blocks)

  security_group_id = aws_security_group.ubuntu_ec2_security_group.id
  description       = "RDP from ${each.value}"
  ip_protocol       = "tcp"
  from_port         = var.rdp_port
  to_port           = var.rdp_port
  cidr_ipv4         = each.value
}
resource "aws_vpc_security_group_egress_rule" "ubuntu_ec2_egress" {
  security_group_id = aws_security_group.ubuntu_ec2_security_group.id
  description       = "All outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
resource "aws_iam_role" "ubuntu_ec2_iam_role" {
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
# for_each over the policy list rather than one attachment resource per policy,
# so a caller can add or remove a policy without the module changing (rules.md
# B-7). toset is safe here because the ARNs are literal strings in
# configuration and are therefore known at plan time (rules.md B-8).
resource "aws_iam_role_policy_attachment" "ubuntu_ec2_iam_role" {
  for_each   = toset(var.iam_policy_arns)
  role       = aws_iam_role.ubuntu_ec2_iam_role.name
  policy_arn = each.value
}
resource "aws_iam_instance_profile" "ubuntu_ec2_instance_profile" {
  # An instance profile holds at most one role, so this attribute is a single
  # role name string - not the list CloudFormation's AWS::IAM::InstanceProfile
  # Roles property takes. jsonencode([...]) here would send the literal string
  # ["terraform-..."] as roleName, which IAM rejects during apply while
  # terraform validate and plan both pass, because the attribute is a string
  # either way (rules.md A-3).
  role = aws_iam_role.ubuntu_ec2_iam_role.name
}
locals {
  # The order of this script is the whole reason RDP works, so it is worth
  # stating before reading it.
  #
  # Installing ubuntu-desktop pulls in NetworkManager, and NetworkManager takes
  # the primary interface over from systemd-networkd while the install is still
  # running. The handover drops the link and DNS stops resolving, and it does
  # not recover on its own - the instance stays unreachable until it reboots.
  #
  # The _monolithic template installed the desktop immediately after setting the
  # password, which put "apt install -yq xrdp" directly after it. That fetch
  # failed with "Temporary failure resolving", so there was no xrdp package, no
  # xrdp user for "adduser xrdp ssl-cert" to find and no xrdp.service to enable,
  # and the instance was left with a dead network as well.
  #
  # So the desktop goes last, after everything that needs the network, and the
  # reboot that restores reachability goes after it.
  user_data = <<-EOT
    #!/bin/bash
    set -x

    apt update -yq
    apt upgrade -yq
    apt install -yq git
    apt install -yq python3 python3-pip python3-venv
    # jq is required by the env.sh helper written onto the Desktop below, which
    # pipes the instance credentials through it. The _monolithic template wrote
    # that script without installing jq, so every line of it failed with
    # "jq: command not found" the first time anyone sourced it.
    apt install -yq jq
    ln -sf /usr/bin/python3 /usr/bin/python
    cd /home/ubuntu

    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc
    tee /etc/apt/sources.list.d/docker.sources <<DOCKERSOURCES
    Types: deb
    URIs: https://download.docker.com/linux/ubuntu
    Suites: $(. /etc/os-release && echo "$${UBUNTU_CODENAME:-$VERSION_CODENAME}")
    Components: stable
    Signed-By: /etc/apt/keyrings/docker.asc
    DOCKERSOURCES
    apt update -yq
    apt install -yq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    systemctl enable --now docker
    usermod -aG docker ubuntu

    # The RDP credential. xrdp authenticates through PAM against this local
    # account, so this line is what makes the password in the outputs work.
    echo "ubuntu:${var.password}" | chpasswd
    usermod -aG sudo ubuntu

    su - ubuntu <<'UBUNTUSETUP'
    # mkdir -p on both, and scripts/ explicitly: the _monolithic template did
    # "mkdir ~/Desktop" and then redirected into ./scripts/env.sh without ever
    # creating ./scripts, so the redirect failed with "No such file or
    # directory" and the helper was never written. The spirit_of_kiro variant
    # got away with the same line because its git clone created the directory.
    mkdir -p ~/Desktop/scripts
    cd ~/Desktop
    # A quoted heredoc rather than echo with a single-quoted body. The template
    # used echo, which closed its quote at the jq filter and reopened it after,
    # so 'jq -r '.AccessKeyId'' landed in the file as unquoted jq -r
    # .AccessKeyId. That happens to be valid jq, which is why it worked, but it
    # only worked by accident.
    cat > ./scripts/env.sh <<'ENVSH'
    #!/bin/bash
    export TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
    export IAM_ROLE=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/iam/security-credentials/)
    export CREDENTIALS=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/iam/security-credentials/$IAM_ROLE)
    export AWS_ACCESS_KEY_ID=$(echo $CREDENTIALS | jq -r '.AccessKeyId')
    export AWS_SECRET_ACCESS_KEY=$(echo $CREDENTIALS | jq -r '.SecretAccessKey')
    export AWS_SESSION_TOKEN=$(echo $CREDENTIALS | jq -r '.Token')
    echo -e "\n"
    echo -e "AWS_ACCESS_KEY_ID : $AWS_ACCESS_KEY_ID \n\nAWS_SECRET_ACCESS_KEY : $AWS_SECRET_ACCESS_KEY \n\nAWS_SESSION_TOKEN : $AWS_SESSION_TOKEN\n"

    # source ./scripts/env.sh
    ENVSH
    chmod +x ./scripts/env.sh
    UBUNTUSETUP

    # xrdp before the desktop, while DNS still resolves. adduser adds the xrdp
    # service account to ssl-cert so it can read /etc/xrdp/key.pem; without it
    # the service starts but every session fails on the TLS handshake.
    apt install -yq xrdp
    systemctl enable --now xrdp
    adduser xrdp ssl-cert
    systemctl restart xrdp

    # A virtualenv for the person using the desktop. The _monolithic template
    # created this one only to pip install aws-cfn-bootstrap and call cfn-signal
    # against the CloudFormation stack that the CreationPolicy was waiting on.
    # There is no stack here - the conversion already notes the CreationPolicy
    # is not reproduced - and that call failed with "cfn-signal: command not
    # found" on every run, so the bootstrap download and the signal are dropped
    # and the virtualenv is kept.
    mkdir -p /home/ubuntu/.venv
    python -m venv /home/ubuntu/.venv
    chown -R ubuntu:ubuntu /home/ubuntu/.venv

    # Anything the caller injected, rendered through a template directive rather
    # than interpolated unconditionally (rules.md B-4). coalesce does not work
    # here: it rejects an empty string as well as null, so coalesce(null, "")
    # fails the plan with "no non-null, non-empty-string arguments".
    %{if var.additional_user_data != null~}
    ${var.additional_user_data}
    %{endif~}

    # Last, for the reason described above this heredoc.
    DEBIAN_FRONTEND=noninteractive apt install -yq ubuntu-desktop

    # The handover does not heal on its own, so reachability has to be restored
    # by a reboot. xrdp is already enabled, so it comes back listening.
    #
    # Detached rather than called inline: this script is cloud-init's
    # scripts-user module, and rebooting before it returns leaves the module's
    # semaphore unwritten, which makes cloud-init run the whole userdata again
    # on the next boot - and reboot again.
    setsid bash -c 'sleep ${var.reboot_delay_seconds}; systemctl reboot' < /dev/null > /dev/null 2>&1 &
    EOT
}
resource "aws_instance" "ubuntu_ec2" {
  ami                         = var.ami_id
  instance_type               = var.instance_type
  key_name                    = var.key_name
  subnet_id                   = var.subnet_id
  associate_public_ip_address = var.associate_public_ip_address
  vpc_security_group_ids      = [aws_security_group.ubuntu_ec2_security_group.id]
  iam_instance_profile        = aws_iam_instance_profile.ubuntu_ec2_instance_profile.name
  user_data                   = local.user_data
  tags = {
    Name = var.instance_name
  }
  root_block_device {
    volume_type           = var.root_volume_type
    volume_size           = var.root_volume_size
    delete_on_termination = true
    encrypted             = var.root_volume_encrypted
  }

  # The instance profile reference orders this after the profile and the role,
  # but not after the policy attachment - nothing in this resource refers to it.
  # The userdata does not call AWS, so a missing policy would not fail the
  # launch; it would surface later as the env.sh helper handing out credentials
  # that can do nothing (rules.md D-1).
  depends_on = [aws_iam_role_policy_attachment.ubuntu_ec2_iam_role]
}
