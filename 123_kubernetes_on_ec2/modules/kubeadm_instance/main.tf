data "aws_ssm_parameter" "ami_id" {
  name = var.ami_ssm_parameter_name
}

resource "aws_iam_role" "instance" {
  name_prefix = "${var.name}-"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "instance" {
  for_each   = toset(var.iam_policy_arns)
  role       = aws_iam_role.instance.name
  policy_arn = each.value
}

# A second attachment resource rather than more entries in the list above, because
# these ARNs come from elsewhere in the configuration and are unknown until apply.
# toset() would make the value its own for_each key, and an unknown key fails the
# plan with "Invalid for_each argument" (rules.md B-8).
resource "aws_iam_role_policy_attachment" "instance_additional" {
  for_each   = var.additional_iam_policies
  role       = aws_iam_role.instance.name
  policy_arn = each.value
}

# role, not jsonencode([role]). An instance profile holds at most one role, so the
# provider takes a single name string. The _monolithic template carried
# jsonencode([...]) on all three of its profiles - a straight transcription of
# CloudFormation's Roles list - and that fails at apply with an IAM API error
# (rules.md A-3).
resource "aws_iam_instance_profile" "instance" {
  name_prefix = "${var.name}-"
  role        = aws_iam_role.instance.name
}

locals {
  # Everything a kubeadm machine needs before kubeadm itself, identical on a control
  # plane and on a worker. Rendered once here rather than pasted into two instances'
  # user data, which is what the _monolithic template did - two copies of forty lines
  # that had to be kept in step by hand.
  #
  # What each part is for:
  #
  #   swapoff        The kubelet refuses to start with swap enabled unless it is told
  #                  to tolerate it. The fstab edit is what makes it survive a reboot.
  #   overlay        containerd's snapshotter needs it.
  #   br_netfilter   Without it the two bridge-nf sysctls below do not exist, and
  #                  pod-to-pod traffic across the bridge bypasses iptables - so
  #                  Services silently do not work.
  #   ip_forward     Routing between the pod network and the node.
  #   SystemdCgroup  The kubelet and containerd have to agree on the cgroup driver.
  #                  Disagreeing produces a kubelet that starts, fails to run pods,
  #                  and logs about cgroups rather than about configuration.
  common_user_data = <<-EOT
    set -x
    dnf update -yq

    swapoff -a
    sed -ri '/\sswap\s/s/^/#/' /etc/fstab

    cat <<'MODULES' | tee /etc/modules-load.d/k8s.conf >/dev/null
    overlay
    br_netfilter
    MODULES
    modprobe overlay
    modprobe br_netfilter

    cat <<'SYSCTL' | tee /etc/sysctl.d/99-kubernetes-cri.conf >/dev/null
    net.bridge.bridge-nf-call-iptables  = 1
    net.bridge.bridge-nf-call-ip6tables = 1
    net.ipv4.ip_forward                 = 1
    SYSCTL
    sysctl -p /etc/sysctl.d/99-kubernetes-cri.conf > /dev/null

    dnf install -yq containerd
    mkdir -p /etc/containerd
    containerd config default | tee /etc/containerd/config.toml > /dev/null
    sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
    systemctl enable --now containerd

    # A pinned minor version, not $(curl dl.k8s.io/release/stable.txt). The
    # _monolithic template read the current stable release at boot, so the two
    # machines could install different minors if they booted either side of a
    # release - and kubeadm rejects a worker more than one minor from the control
    # plane. Pinning also keeps the kubectl on the workbench inside the supported
    # skew (rules.md H-1).
    cat <<'REPO' | tee /etc/yum.repos.d/kubernetes.repo > /dev/null
    [kubernetes]
    name=Kubernetes
    baseurl=https://pkgs.k8s.io/core:/stable:/${var.kubernetes_minor_version}/rpm/
    enabled=1
    gpgcheck=1
    gpgkey=https://pkgs.k8s.io/core:/stable:/${var.kubernetes_minor_version}/rpm/repodata/repomd.xml.key
    exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
    REPO

    dnf install -yq kubelet kubeadm kubectl --disableexcludes=kubernetes
    systemctl enable --now kubelet
    EOT
}

resource "aws_instance" "instance" {
  ami                         = data.aws_ssm_parameter.ami_id.insecure_value
  instance_type               = var.instance_type
  key_name                    = var.key_name
  subnet_id                   = var.subnet_id
  associate_public_ip_address = var.associate_public_ip_address
  vpc_security_group_ids      = var.vpc_security_group_ids
  iam_instance_profile        = aws_iam_instance_profile.instance.name

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
    encrypted   = true
  }

  metadata_options {
    http_endpoint = "enabled"
    # required, so IMDSv1 is off. The user data below reads the instance's own
    # address from IMDS and does so with a token, which is why this can be required
    # rather than optional.
    http_tokens                 = "required"
    http_put_response_hop_limit = var.instance_metadata_http_put_response_hop_limit
  }

  # The role-specific half - kubeadm init on a control plane, kubeadm join on a
  # worker - comes last, after the common preparation. The marker file, when the
  # caller asked for one, is the very last thing written: touching it earlier would
  # release whatever is waiting on it while this script is still running
  # (rules.md B-4/D-5).
  user_data = <<-EOT
    #!/bin/bash
    ${local.common_user_data}
    ${var.additional_user_data}
    %{if var.marker_file_path != null~}
    mkdir -p ${var.marker_file_path}
    touch ${var.marker_file_path}/userdata
    %{endif~}
    EOT

  tags = {
    Name = var.name
  }

  # EC2 accepts the run call before IAM has finished propagating the profile, and the
  # instance then boots with a role that cannot call anything - so every aws command
  # in the user data fails with an access denied that looks like a missing policy
  # rather than a race (rules.md D-1).
  depends_on = [
    aws_iam_role_policy_attachment.instance,
    aws_iam_role_policy_attachment.instance_additional,
  ]
}
