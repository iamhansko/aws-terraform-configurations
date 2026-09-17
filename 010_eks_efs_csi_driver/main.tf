data "aws_region" "current" {}
module "network" {
  source = "./modules/network"

  vpc_cidr_block           = var.vpc_cidr_block
  vpc_name                 = "${var.prefix}-vpc"
  internet_gateway_name    = "${var.prefix}-igw"
  public_subnet_name       = "${var.prefix}-public"
  private_subnet_name      = "${var.prefix}-private"
  public_route_table_name  = "${var.prefix}-public-rt"
  private_route_table_name = "${var.prefix}-private-rt"
  nat_gateway_name         = "${var.prefix}-natgw"
}
module "key_pair" {
  source = "./modules/key_pair"

  key_name = var.key_name

  # key_pair consumes no network output, so nothing would otherwise order it
  # against the network module's resources. Every module in a root that has a
  # network module waits for all of it (rules.md D-3).
  depends_on = [module.network]
}
module "eks_cluster" {
  source = "./modules/eks_cluster"

  name                   = var.cluster_name
  kubernetes_version     = var.kubernetes_version
  subnet_ids             = concat(module.network.public_subnet_ids, module.network.private_subnet_ids)
  endpoint_public_access = var.endpoint_public_access
  public_access_cidrs    = var.public_access_cidrs

  # Referencing module.network.*_subnet_ids only orders this module after the
  # specific aws_subnet resources behind those outputs, not after the NAT
  # gateways and route table associations that never surface as outputs
  # (rules.md D-3).
  depends_on = [module.network]
}
module "eks_vpc_cni_addon" {
  source = "./modules/eks_vpc_cni_addon"

  cluster_name = module.eks_cluster.cluster_name

  # bootstrap_self_managed_addons = false on the cluster means vpc-cni does not
  # exist until this addon creates it. As a DaemonSet it reaches ACTIVE with
  # zero nodes, so it is created before any node capacity - worker nodes need it
  # running to join the cluster Ready (rules.md C-4).
  depends_on = [module.network, module.eks_cluster]
}
module "eks_kube_proxy_addon" {
  source = "./modules/eks_kube_proxy_addon"

  cluster_name = module.eks_cluster.cluster_name

  # Same reasoning as eks_vpc_cni_addon: kube-proxy is a DaemonSet and must
  # exist before any node capacity (rules.md C-4).
  depends_on = [module.network, module.eks_cluster]
}
module "eks_node_group" {
  source = "./modules/eks_node_group"

  cluster_name    = module.eks_cluster.cluster_name
  node_group_name = var.node_group_name
  instance_types  = var.node_group_instance_types
  labels          = var.node_group_labels
  desired_size    = var.node_group_desired_size
  min_size        = var.node_group_min_size
  max_size        = var.node_group_max_size
  subnet_ids      = module.network.private_subnet_ids
  key_name        = module.key_pair.key_name

  # Nodes need vpc-cni and kube-proxy running to join the cluster Ready
  # (rules.md C-4).
  depends_on = [module.network, module.eks_vpc_cni_addon, module.eks_kube_proxy_addon]
}
module "eks_coredns_addon" {
  source = "./modules/eks_coredns_addon"

  cluster_name = module.eks_cluster.cluster_name

  # coredns is a Deployment and needs schedulable node capacity to leave its
  # DEGRADED state and become ACTIVE, so it is created after the node group
  # rather than before it (rules.md C-4).
  depends_on = [module.eks_node_group]
}
# The file system itself is plain AWS infrastructure with no Kubernetes in it,
# so it is its own module: the CSI driver addon consumes nothing from it, and
# the StorageClass only needs its ID.
module "efs_file_system" {
  source = "./modules/efs_file_system"

  name                = "${var.prefix}-efs"
  vpc_id              = module.network.vpc_id
  performance_mode    = var.efs_performance_mode
  throughput_mode     = var.efs_throughput_mode
  security_group_name = "${var.prefix}-efs-sg"
  mount_target_subnet_ids = {
    # Literal keys with the subnet IDs as values, because a mount target per
    # zone has to be planned before those IDs are known (rules.md B-8).
    a = module.network.private_subnet_a_id
    b = module.network.private_subnet_b_id
    c = module.network.private_subnet_c_id
  }
  # NFS is admitted from the cluster security group rather than the whole VPC
  # CIDR the _monolithic template opened: worker nodes and the VS Code instance
  # both belong to that group, so the rule follows the workloads instead of the
  # address space. The module is handed an ID map and never learns that it
  # belongs to an EKS cluster (rules.md B-6).
  ingress_source_security_groups = {
    eks_cluster = module.eks_cluster.cluster_security_group_id
  }

  depends_on = [module.network]
}
module "eks_efs_csi_driver_addon" {
  source = "./modules/eks_efs_csi_driver_addon"

  cluster_name      = module.eks_cluster.cluster_name
  oidc_provider_arn = module.eks_cluster.oidc_provider_arn
  oidc_issuer_host  = module.eks_cluster.oidc_issuer_host
  addon_version     = var.efs_csi_driver_addon_version

  # The driver's controller is a Deployment, so like coredns it needs
  # schedulable capacity to become ACTIVE rather than DEGRADED (rules.md C-4).
  depends_on = [module.network, module.eks_node_group]
}
module "efs_storage_class" {
  source = "./modules/efs_storage_class"

  storage_class_name = var.storage_class_name
  # Takes the driver name from the addon module and the file system ID from the
  # file system module, rather than repeating "efs.csi.aws.com" or leaving the
  # _monolithic template's FILE_SYSTEM_ID placeholder to be filled in by hand
  # (rules.md B-5).
  provisioner          = module.eks_efs_csi_driver_addon.provisioner
  file_system_id       = module.efs_file_system.file_system_id
  directory_perms      = var.storage_class_directory_perms
  create_demo_workload = var.create_demo_workload
  demo_replica_count   = var.demo_replica_count

  # These are kubectl_manifest resources talking straight to the cluster's API
  # server, and the access point behind the claim is created by the EFS CSI
  # controller running on the node group. Ordering the module after both the
  # addon and the node group makes terraform destroy delete the claim - letting
  # the controller remove the access point - before either disappears
  # (rules.md D-4).
  depends_on = [module.network, module.eks_node_group, module.eks_efs_csi_driver_addon, module.efs_file_system]
}
module "vscode_ec2" {
  source = "./modules/vscode_ec2"

  vpc_id                      = module.network.vpc_id
  subnet_id                   = module.network.public_subnet_a_id
  key_name                    = module.key_pair.key_name
  instance_type               = var.vscode_instance_type
  allow_inbound_from_anywhere = var.allow_inbound_from_anywhere
  # Lets the README association below know when the bootstrap has finished
  # (rules.md H-2). The module touches <path>/userdata as its last step.
  marker_file_path = var.marker_file_path
  # Joining the cluster security group is what lets this instance reach the
  # private API server endpoint, and it is also what the EFS security group
  # admits NFS from. The module is handed an ID list and never learns that it
  # belongs to an EKS cluster (rules.md B-6).
  extra_security_group_ids = [module.eks_cluster.cluster_security_group_id]
  # An EKS cluster and this instance live in the same root module, so the
  # instance is the workbench for that cluster and carries all five tools:
  # code-server (the module itself), plus kubectl, eksctl, helm and docker
  # (rules.md H-1). None of them is used to create resources - that stays with
  # the kubectl provider (rules.md E-1).
  additional_user_data = <<-EOT
    dnf install -yq python3.13
    ln -sf /usr/bin/python3.13 /usr/bin/python
    python -m ensurepip --upgrade
    # Building container images needs a real daemon on the host, so unlike the
    # kubectl/helm steps this cannot become a provider resource (rules.md E-1).
    dnf install -yq docker
    systemctl enable --now docker
    usermod -aG docker ec2-user
    # code-server is already running from the module's bootstrap, so its process
    # predates the docker group and its integrated terminals inherit the groups
    # that process started with. Restarting picks the group up, which is what
    # makes docker usable from the IDE without loosening the socket's
    # permissions (rules.md H-1).
    systemctl restart code-server
    # Runs as ec2-user with HOME pinned: user data runs as root, so "~" can
    # still resolve to /root and the tools plus kubeconfig would land somewhere
    # the code-server session cannot see (rules.md H-1).
    sudo -Eu ec2-user bash << 'EOF'
    export HOME=/home/ec2-user
    cd $HOME
    mkdir -p $HOME/bin
    curl -sO https://s3.us-west-2.amazonaws.com/amazon-eks/${var.kubectl_download_version}/bin/linux/amd64/kubectl
    chmod +x ./kubectl && mv ./kubectl $HOME/bin/kubectl
    export PATH=$HOME/bin:$PATH
    echo 'export PATH=$HOME/bin:$PATH' >> ~/.bashrc
    # Order matters: sourcing the completion defines __start_kubectl, so a
    # "complete" line placed before it fails on every login.
    echo 'source /usr/share/bash-completion/bash_completion' >> ~/.bashrc
    echo 'source <(kubectl completion bash)' >> ~/.bashrc
    echo 'alias k=kubectl' >> ~/.bashrc
    echo 'complete -o default -F __start_kubectl k' >> ~/.bashrc
    PLATFORM=$(uname -s)_amd64
    curl -sLO "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_$PLATFORM.tar.gz"
    tar -xzf eksctl_$PLATFORM.tar.gz -C /tmp && rm eksctl_$PLATFORM.tar.gz
    sudo install -m 0755 /tmp/eksctl /usr/local/bin && rm /tmp/eksctl
    curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
    chmod 700 get_helm.sh && ./get_helm.sh
    aws configure set default.region ${data.aws_region.current.region}
    aws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${module.eks_cluster.cluster_name}
    EOF
  EOT

  depends_on = [module.network]
}
# Granting the instance role cluster access joins two modules that know nothing
# about each other, so it belongs in the root rather than inside either one
# (rules.md C-1). Without it kubectl is installed but every call fails with
# "You must be logged in to the server" (rules.md H-1).
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
  # Every output this project exposes, defined once. outputs.tf projects these
  # and the README below renders them, so no value is written twice (rules.md
  # #5/#35). Adding an entry here is what makes an output possible, which is
  # what keeps the README from silently falling behind outputs.tf.
  outputs = {
    vscode_url = {
      order       = 1
      title       = "code-server"
      description = "Open the IDE here. The rest of these commands are meant to be run from its terminal"
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
      description = "API server endpoint of the EKS cluster"
      value       = module.eks_cluster.cluster_endpoint
    }
    file_system_id = {
      order       = 4
      title       = "EFS file system"
      description = "File system the StorageClass provisions access points in. This is the value the _monolithic manifests left as a FILE_SYSTEM_ID placeholder"
      value       = module.efs_file_system.file_system_id
    }
    efs_csi_driver_controller_role_arn = {
      order       = 5
      title       = "EFS CSI controller IAM role"
      description = "Role the EFS CSI controller assumes through IRSA to create and delete access points"
      value       = module.eks_efs_csi_driver_addon.controller_role_arn
    }
    storage_class_name = {
      order       = 6
      title       = "StorageClass"
      description = "StorageClass backed by the EFS CSI driver, in efs-ap mode so each claim gets its own access point"
      value       = module.efs_storage_class.storage_class_name
    }
    demo_claim_name = {
      order       = 7
      title       = "Demo PersistentVolumeClaim"
      description = "ReadWriteMany claim every demo replica mounts at once, or null when create_demo_workload is false"
      value       = module.efs_storage_class.demo_claim_name
    }
    demo_pods_command = {
      order       = 8
      title       = "1. Check where the replicas landed"
      description = "Lists the demo pods with their nodes. Replicas on different nodes and zones sharing one volume is what ReadWriteMany buys over the EBS driver"
      value       = module.efs_storage_class.demo_pods_command
    }
    demo_shared_file_command = {
      order       = 9
      title       = "2. Read the shared file"
      description = "Tails the file all replicas append to. Interleaved hostnames prove they are writing to the same volume"
      value       = module.efs_storage_class.demo_shared_file_command
    }
  }
  # Iterating local.outputs directly would order sections by key, which puts
  # "2. Read the shared file" above "1. Check where the replicas landed".
  # Re-keying by the order field and taking values() sorts by that instead -
  # values() returns a map's values ordered by key - so the README reads in the
  # order the demo is run, and the order is still fully determined by the
  # configuration rather than shuffling between applies.
  readme_ordered = values({
    for key, entry in local.outputs : format("%02d-%s", entry.order, key) => entry
  })
  # Rendered from the same map, so an added output shows up here without anyone
  # remembering to edit two places (rules.md H-2).
  readme_body = join("\n", concat(
    ["# ${var.cluster_name}", ""],
    flatten([for entry in local.readme_ordered : [
      "## ${entry.title}", "", entry.description, "", "```", entry.value, "```", "",
    ]]),
  ))
}
# The work happens inside code-server in a browser, where "terraform output" is
# not available, so every output above is also written to a README in the home
# directory the IDE opens (rules.md H-2).
resource "aws_ssm_association" "vscode_readme" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = var.readme_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    # The until loop, not depends_on or wait_for_success_timeout_seconds, is
    # what orders this after the instance bootstrap, and the marker this command
    # leaves behind is what a later association would wait on (rules.md D-5).
    # SSM runs as root, hence the chown - without it the file is not editable
    # from the IDE.
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
