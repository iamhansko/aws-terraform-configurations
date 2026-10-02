data "aws_region" "current" {}
module "network" {
  source = "./modules/network"
}
module "key_pair" {
  source = "./modules/key_pair"

  key_name = var.key_name

  # key_pair consumes no network output, so nothing would otherwise order it against
  # the network module's resources (rules.md D-3).
  depends_on = [module.network]
}
module "eks_cluster" {
  source = "./modules/eks_cluster"

  name                   = var.cluster_name
  kubernetes_version     = var.kubernetes_version
  subnet_ids             = concat(module.network.public_subnet_ids, module.network.private_subnet_ids)
  endpoint_public_access = var.endpoint_public_access
  public_access_cidrs    = var.public_access_cidrs

  # Referencing module.network.*_subnet_ids only orders this after the specific
  # aws_subnet resources behind those outputs, not after the NAT gateways and route
  # table associations that never surface as outputs (rules.md D-3).
  depends_on = [module.network]
}
module "eks_vpc_cni_addon" {
  source = "./modules/eks_vpc_cni_addon"

  cluster_name = module.eks_cluster.cluster_name

  # bootstrap_self_managed_addons = false on the cluster means vpc-cni does not exist
  # until this addon creates it. As a DaemonSet it reaches ACTIVE with zero nodes, so it
  # comes before any capacity (rules.md C-4) - and nodes need it to join Ready.
  depends_on = [module.network, module.eks_cluster]
}
module "eks_kube_proxy_addon" {
  source = "./modules/eks_kube_proxy_addon"

  cluster_name = module.eks_cluster.cluster_name

  # Same reasoning as eks_vpc_cni_addon (rules.md C-4).
  depends_on = [module.network, module.eks_cluster]
}
locals {
  # The variant, as a script.
  #
  # Two facts decide its shape. First, the volume is not where it was asked for: on a
  # Nitro instance EC2 records the block device mapping name but the kernel exposes
  # every EBS volume as /dev/nvme<N>n1 in attach order. amazon-ec2-utils, which the
  # EKS-optimized AMIs carry, ships udev rules that recreate a symlink at the mapping
  # name, so the mapping name is addressable - the _monolithic template instead wrote
  # /dev/nvme1n1 directly, which is a guess that happens to hold while the root volume
  # is the only other one.
  #
  # Second, and more important: the AWS guidance this project comes from is written for
  # Amazon Linux 2 and says so - "This feature is supported on AL2 only; it is not yet
  # supported on AL2023". The reason is ordering, not capability. On AL2 the equivalent
  # commands ran as preBootstrapCommands, before bootstrap.sh started containerd and
  # the kubelet, so stopping containerd and moving its data was deterministic. On AL2023
  # the node is brought up by nodeadm from systemd units, and a user shell script part
  # runs in cloud-init's final stage - which can land after containerd has already
  # started, leaving the runtime's state directory replaced underneath it.
  #
  # So this is a cloud-config bootcmd rather than a shell script part. bootcmd runs in
  # cloud-init's first stage, before the network stage and therefore before anything
  # ordered after cloud-init - which is everything that could start containerd. Nothing
  # has to be stopped, nothing is deleted, and the AMI's pre-imported sandbox image is
  # copied onto the new volume instead of wiped, which is why there is no
  # "ctr image import" step to put it back.
  #
  # bootcmd also runs on every boot, so each step is guarded: the filesystem is only
  # created when the device has none, the seed copy only happens when it was just
  # created, and the fstab entry - which the _monolithic template never wrote, so its
  # mount was lost on the first reboot - means the mount is already there on later boots.
  node_container_volume_bootcmd = <<-EOT
    set -eu
    DEVICE="${var.container_volume_device_name}"
    MOUNT="${var.container_data_path}"

    # Wait for the udev symlink rather than assuming an nvme index.
    for _ in $(seq 1 60); do
      [ -e "$DEVICE" ] && break
      sleep 1
    done
    if [ ! -e "$DEVICE" ]; then
      echo "container volume $DEVICE never appeared" >&2
      exit 1
    fi

    mkdir -p "$MOUNT"
    # Already mounted, which is the normal case on every boot after the first, because
    # of the fstab entry below.
    if mountpoint -q "$MOUNT"; then
      exit 0
    fi

    FRESH=no
    if ! blkid "$DEVICE" >/dev/null 2>&1; then
      mkfs -t ext4 -L containerd "$DEVICE"
      FRESH=yes
    fi

    # Seed the new filesystem from the AMI's own copy of the directory, which holds the
    # pre-imported pause image. Deleting it instead - as the _monolithic template did -
    # is what made that image have to be re-imported afterwards.
    if [ "$FRESH" = yes ]; then
      mkdir -p /mnt/container-volume-seed
      mount "$DEVICE" /mnt/container-volume-seed
      cp -a "$MOUNT"/. /mnt/container-volume-seed/
      umount /mnt/container-volume-seed
      rmdir /mnt/container-volume-seed
    fi

    # By UUID, because the nvme index this symlink points at is not stable across
    # reboots. nofail so a missing volume degrades to a node running on its root volume
    # rather than one that will not boot.
    UUID="$(blkid -s UUID -o value "$DEVICE")"
    if ! grep -q " $MOUNT " /etc/fstab; then
      echo "UUID=$UUID $MOUNT ext4 defaults,noatime,nofail 0 2" >> /etc/fstab
    fi
    mount "$MOUNT"
    EOT
  # EKS only reads user data on AL2023 as a MIME multipart document: a bare shell script
  # or a bare cloud-config is accepted by the launch template and then ignored. EKS
  # appends its own NodeConfig part to this document, which is why none is written here
  # - custom_ami_id is null, so the AMI is the EKS-optimized one and EKS still supplies
  # the bootstrap configuration (rules.md B-4).
  node_user_data = <<-EOT
    MIME-Version: 1.0
    Content-Type: multipart/mixed; boundary="==TFBOUNDARY=="

    --==TFBOUNDARY==
    Content-Type: text/cloud-config; charset="us-ascii"

    #cloud-config
    timezone: ${var.node_timezone}
    bootcmd:
      - |
        ${indent(4, local.node_container_volume_bootcmd)}

    --==TFBOUNDARY==--
    EOT
}
module "eks_node_group" {
  source = "./modules/eks_node_group"

  cluster_name   = module.eks_cluster.cluster_name
  instance_types = var.node_group_instance_types
  desired_size   = var.node_group_desired_size
  min_size       = var.node_group_min_size
  max_size       = var.node_group_max_size
  subnet_ids     = module.network.private_subnet_ids
  # Attached so the nodes can be reached over SSH if the container runtime is the thing
  # being debugged, which SSM Session Manager also covers.
  key_name = module.key_pair.key_name
  # The variant. One volume, named by the same variable the script above addresses, so
  # the mapping and the mount cannot disagree (rules.md B-5).
  additional_block_device_mappings = [{
    device_name = var.container_volume_device_name
    volume_size = var.container_volume_size
    volume_type = var.container_volume_type
    encrypted   = var.container_volume_encrypted
  }]
  custom_user_data = local.node_user_data

  depends_on = [module.network, module.eks_vpc_cni_addon, module.eks_kube_proxy_addon]
}
module "eks_coredns_addon" {
  source = "./modules/eks_coredns_addon"

  cluster_name = module.eks_cluster.cluster_name

  # coredns is a Deployment and needs schedulable capacity to leave DEGRADED and become
  # ACTIVE (rules.md C-4).
  depends_on = [
  module.network, module.eks_node_group]
}
module "vscode_ec2" {
  source = "./modules/vscode_ec2"

  vpc_id                      = module.network.vpc_id
  subnet_id                   = module.network.public_subnet_a_id
  key_name                    = module.key_pair.key_name
  instance_type               = var.vscode_instance_type
  allow_inbound_from_anywhere = var.allow_inbound_from_anywhere
  marker_file_path            = var.marker_file_path
  # Joining the cluster security group is what lets this instance reach the API server.
  # The module is handed an ID list and never learns it belongs to an EKS cluster
  # (rules.md B-6).
  extra_security_group_ids = [module.eks_cluster.cluster_security_group_id]

  # An EKS cluster and this instance share a root module, so it is the workbench for that
  # cluster and carries all five tools (rules.md H-1). None of them creates anything here
  # - there is nothing inside the cluster for this project to create - but they are what
  # the checks in the outputs are run with.
  #
  # Two bugs from the _monolithic template are fixed here rather than carried over. It
  # ran "exec bash" partway through, which replaces the shell and silently discarded
  # every remaining line - update-kubeconfig, eksctl and helm were all after it, so the
  # instance came up without a kubeconfig. And it pulled eksctl from weaveworks;
  # eksctl-io is the project's own org (rules.md H-1).
  additional_user_data = <<-EOT
    dnf install -yq docker
    systemctl enable --now docker
    usermod -aG docker ec2-user
    # code-server is already running and predates the docker group, so its terminals
    # would not have it without a restart.
    systemctl restart code-server

    sudo -Eu ec2-user bash << 'EOF'
    export HOME=/home/ec2-user
    cd /home/ec2-user
    mkdir -p /home/ec2-user/bin
    curl -sO https://s3.us-west-2.amazonaws.com/amazon-eks/${var.kubectl_download_version}/bin/linux/amd64/kubectl
    chmod +x kubectl
    mv kubectl /home/ec2-user/bin/kubectl
    export PATH=/home/ec2-user/bin:$PATH
    echo 'export PATH=/home/ec2-user/bin:$PATH' >> ~/.bashrc
    # Order matters: kubectl's completion defines __start_kubectl, and that has to exist
    # before complete names it, or every login prints "function not found"
    # (rules.md H-1).
    echo 'source /usr/share/bash-completion/bash_completion' >> ~/.bashrc
    echo 'source <(kubectl completion bash)' >> ~/.bashrc
    echo 'alias k=kubectl' >> ~/.bashrc
    echo 'complete -o default -F __start_kubectl k' >> ~/.bashrc
    PLATFORM=$(uname -s)_amd64
    curl -sLO "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_$PLATFORM.tar.gz"
    tar -xzf eksctl_$PLATFORM.tar.gz -C /tmp && rm eksctl_$PLATFORM.tar.gz
    sudo install -m 0755 /tmp/eksctl /usr/local/bin && rm /tmp/eksctl
    curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
    chmod 700 get_helm.sh
    ./get_helm.sh
    aws configure set default.region ${data.aws_region.current.region}
    aws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${module.eks_cluster.cluster_name}
    EOF
  EOT

  depends_on = [module.network]
}
# Granting the bastion's instance role cluster access joins two modules that know nothing
# about each other, so it belongs in the root (rules.md C-1).
resource "aws_eks_access_entry" "vscode_access_entry" {
  cluster_name  = module.eks_cluster.cluster_name
  principal_arn = module.vscode_ec2.iam_role_arn
  type          = "STANDARD"
}
resource "aws_eks_access_policy_association" "vscode_access_policy_association" {
  cluster_name  = module.eks_cluster.cluster_name
  principal_arn = module.vscode_ec2.iam_role_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.vscode_access_entry]
}
locals {
  # A node-level change has no Kubernetes object to inspect, so the checks below are all
  # run on a node rather than against the API server. Session Manager reaches them
  # without a bastion hop or a key pair, which is why AmazonSSMManagedInstanceCore is in
  # the node role's default policy list.
  node_id_command = "aws ec2 describe-instances --filters Name=tag:eks:cluster-name,Values=${module.eks_cluster.cluster_name} Name=instance-state-name,Values=running --query 'Reservations[].Instances[].InstanceId' --output text"
  # Every output this project exposes, defined once. outputs.tf projects these and the
  # README below renders them, so no value expression is written twice (rules.md B-5/H-2).
  # Adding an entry here is what makes an output possible, which is what keeps the README
  # from falling behind outputs.tf.
  outputs = {
    vscode_url = {
      order       = 1
      title       = "code-server"
      description = "Open the IDE here. The commands below are meant to be run from its terminal"
      value       = module.vscode_ec2.vscode_url
    }
    cluster_name = {
      order       = 2
      title       = "EKS cluster name"
      description = "Name of the EKS cluster"
      value       = module.eks_cluster.cluster_name
    }
    cluster_endpoint = {
      order       = 3
      title       = "EKS cluster endpoint"
      description = "API server endpoint. Unlike the other EKS projects here, no Terraform provider needed it during apply - nothing in this project creates Kubernetes objects"
      value       = module.eks_cluster.cluster_endpoint
    }
    container_volume = {
      order       = 4
      title       = "The container runtime volume"
      description = "The extra volume attached to every node and the directory it carries. This is the whole change: image layers and container filesystems spend this volume's I/O budget instead of the root volume's, which the kubelet and the operating system need"
      value       = "${var.container_volume_device_name} -> ${var.container_data_path} (${var.container_volume_size} GiB ${var.container_volume_type}, encrypted=${var.container_volume_encrypted})"
    }
    device_naming_note = {
      order       = 5
      title       = "Why the device name is not a path"
      description = "Worth reading before the checks below, because the name above will not be what lsblk shows. These instance types are Nitro-based, so EC2 records the mapping name while the kernel exposes each EBS volume as /dev/nvme<N>n1 in attach order. The udev rules in amazon-ec2-utils recreate a symlink at the mapping name, which is what the setup script addresses - the _monolithic template hardcoded the nvme path instead"
      value       = "ls -l ${var.container_volume_device_name}"
    }
    node_id_command = {
      order       = 6
      title       = "1. List the worker nodes"
      description = "Instance IDs for the node group, for the Session Manager commands that follow. EKS tags them with the cluster name, so no name lookup is needed"
      value       = local.node_id_command
    }
    session_command = {
      order       = 7
      title       = "2. Open a shell on one"
      description = "Session Manager rather than SSH, so this works without the key pair and without an inbound rule. Everything below is run inside that session"
      value       = "aws ssm start-session --target <instance-id>"
    }
    mount_check_command = {
      order       = 8
      title       = "3. Confirm the volume is mounted where it should be"
      description = "The one check that matters. A line for the container data path means the setup ran; no line means containerd is on the root volume, which looks completely normal from Kubernetes - the node is Ready and pods run"
      value       = "findmnt ${var.container_data_path} && lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT"
    }
    fstab_check_command = {
      order       = 9
      title       = "4. Confirm it survives a reboot"
      description = "The mount has to be in fstab or it is lost on the next boot, and containerd silently starts using the root volume again. The _monolithic template mounted the volume and never wrote this entry"
      value       = "grep ${var.container_data_path} /etc/fstab"
    }
    sandbox_image_check_command = {
      order       = 10
      title       = "5. Confirm the AMI's sandbox image came across"
      description = "The pause image ships pre-imported in the AMI's copy of the data directory, so mounting an empty volume over it hides it. The setup copies the directory across instead of deleting it, which is why there is no re-import step - this is where that shows"
      value       = "sudo ctr --namespace k8s.io images ls | grep -i pause"
    }
    cloud_init_log_command = {
      order       = 11
      title       = "6. Read what the setup actually did"
      description = "The script runs as a cloud-config bootcmd, in cloud-init's first stage - before anything that could start containerd. That is the deviation from the AWS guidance this project follows, which is written for Amazon Linux 2 and states it is not supported on AL2023: on AL2 the same commands ran before the bootstrap script, while on AL2023 a shell script part can run after containerd has already started"
      value       = "sudo grep -iE 'bootcmd|containerd|nvme|mkfs' /var/log/cloud-init.log | tail -40"
    }
    disk_pressure_command = {
      order       = 12
      title       = "7. See what the kubelet now reports"
      description = "The kubelet's image filesystem is the one containerd uses, so after this change its capacity is the extra volume's rather than the root volume's. That is the number eviction thresholds are measured against"
      value       = "kubectl get --raw /api/v1/nodes/<node-name>/proxy/stats/summary | grep -A6 imagefs"
    }
    update_kubeconfig_command = {
      order       = 13
      title       = "Re-point kubectl"
      description = "User data already ran this, so kubectl works out of the box. Re-run it if the kubeconfig is ever lost"
      value       = "aws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${module.eks_cluster.cluster_name}"
    }
  }
  # Iterating local.outputs directly would order sections by key. Re-keying by the order
  # field and taking values() - which returns a map's values ordered by key - makes the
  # README read top to bottom while the order stays decided by configuration.
  readme_ordered = values({
    for key, entry in local.outputs : format("%02d-%s", entry.order, key) => entry
  })
  readme_body = join("\n", concat(
    ["# ${var.cluster_name}", ""],
    flatten([for entry in local.readme_ordered : [
      "## ${entry.title}", "", entry.description, "", "```", entry.value, "```", "",
    ]]),
  ))
}
# The work happens inside code-server in a browser, where terraform output is not
# available, so every output above is also written to a README in the home directory the
# IDE opens (rules.md H-2). Combining several modules' outputs is the root's job, so this
# lives here rather than inside the instance module.
resource "aws_ssm_association" "vscode_readme" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = var.readme_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    # The until loop, not depends_on or wait_for_success_timeout_seconds, is what orders
    # this after the bootstrap (rules.md D-5). The marker path comes back out of the
    # module it was passed into, so it is defined once (rules.md B-5).
    #
    # SSM runs as root, hence the chown.
    commands = <<-EOT
      until [ -f ${module.vscode_ec2.marker_file_path}/userdata ]; do sleep 10; done
      cat > /home/ec2-user/README.md << 'TFREADME'
      ${local.readme_body}
      TFREADME
      chown ec2-user:ec2-user /home/ec2-user/README.md
      touch ${module.vscode_ec2.marker_file_path}/vscode_readme
      EOT
  }
}
